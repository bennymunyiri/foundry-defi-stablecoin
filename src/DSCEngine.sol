// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Benson Munyiri
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 dollar == 1 token
 * This stablecoin has the properties
 * -Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmatically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed Weth and Wbtc.
 * Our Dsc System should Always be "OverCollaterized". At no point, should the value <= the value of all the DSC.
 * @notice This contract is the core of the Dsce system. It Handles all the logic for mining and redeeming DSC tokens, as well as depositing
 * & withdrawing collateral.
 *
 * @notice  This Contract is VERY loosely based on the MakerDAO DSS (DAI)  system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////
    ///Errors////
    /////////////
    error DSCEngine__ShouldBeMoreThanZero();
    error DSCEngine__NotCorrectNumberOfTokens();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    /// State Variables//
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECESION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUAIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateraldeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////
    /// Events////////////
    //////////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    ///////////////
    /// Modifiers//
    //////////////
    modifier morethanzero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__ShouldBeMoreThanZero();
        }
        _;
    }

    modifier isallowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    /// Functions//
    ///////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        //USD Price Feed
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotCorrectNumberOfTokens();
        }
        uint256 len = tokenAddresses.length;
        for (uint256 i = 0; i < len; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////
    //External/////
    ///////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin  to mint
     * @notice This function will deposit your collateral and allow you to mint DSC stable coin
     */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     *@notice Follows CEI
     * @param tokencollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of the token to be deposited
     */

    function depositCollateral(
        address tokencollateralAddress,
        uint256 amountCollateral
    )
        public
        morethanzero(amountCollateral)
        isallowed(tokencollateralAddress)
        nonReentrant
    {
        s_collateraldeposited[msg.sender][
            tokencollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokencollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokencollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // RedeemCollateral already checks Health Factor
    }

    // In order to redeem Collateral:
    // Health Factor must be over 1 after collateral pulled
    // follows is CEI
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public morethanzero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertifHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDSCToMint The amount of decentralized stablecoin to mint
     * @notice they must have more colllateral value than minimum threshold
     */
    function mintDsc(
        uint256 amountDSCToMint
    ) public morethanzero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertifHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public morethanzero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertifHealthFactorIsBroken(msg.sender);
    }

    // if someone is almost undercollateralized, we will pay you to liquidate them!
    /**
     * @param collateral the erc20 collateral address to liquidate from the user
     * @param user The User who has the broken the health factor. Their _healthFactor should
     * below MIN_HEALTH_FACTOR
     * @param debtToCover The amountof DSC you want to burn to improve the Users health factor
     * @notice you can partially liquadate a user.
     * @notice you will get a liquidation bonus for taking users funds
     * @notice This function working assumes the protocol will be roughly over 200% for this to work
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external morethanzero(debtToCover) nonReentrant {
        // need to check Health Factor
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // want to burn their DSC "DEBT"
        // And take their Collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // and give them a 10% bonus
        // So we are giving
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealth = _healthFactor(user);
        if (endingUserHealth <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertifHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ////////////////////////////////////
    //private & internal functions//////
    ////////////////////////////////////

    /**
     * @dev Low-Level internal function, do not call unless the function calling it
     * is checking for healthfactor is broken
     */

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateraldeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * returns how close to liquadition a user is
     * @param user if user goes below 1, then they can get Liquadated
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total Dsc minted
        // total collateral Value
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUAIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        //return (collateralValueInUsd / totalDSCMinted)
    }

    // do they have enough eth too mint dsc
    // revert if they dont

    function _revertifHealthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userhealthFactor);
        }
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUAIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    ////////////////////////////////////
    //Public & external functions//////
    ////////////////////////////////////
    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // price of Eth(token)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e6) = 5e15
        return (((usdAmountInWei * PRECISION) / uint256(price)) *
            ADDITIONAL_FEED_PRECESION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token get amount in usd
        uint256 len = s_collateralTokens.length;

        for (uint256 i = 0; i < len; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateraldeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1 eth = 1000
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECESION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECESION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUAIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATOR_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateraldeposited[user][token];
    }
}
