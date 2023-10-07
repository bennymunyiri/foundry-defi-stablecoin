/**
 * // SPDX-License-Identifier: MIT
//Have our Invariant aka properties of the contract

// What are our Invariants?

// 1. The total supply of DSC should be less than the total values of collateral

// 2. Getter view functions should never revert <- evergreen Invariant
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSCEngine} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSCEngine deployer;
    DSCEngine dscengine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dsc, dscengine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        targetContract(address(dscengine));
    }

    function invariant_protocolMustHaveMoreValueThanToTalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscengine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscengine));
        uint256 wethValue = dscengine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscengine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue > totalSupply);
    }
}*/
