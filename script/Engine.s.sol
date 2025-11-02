// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {StableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./helperConfig.s.sol";

contract DeployEngineScript is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, StableCoin, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        StableCoin stablecoin = new StableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(stablecoin));
        stablecoin.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (engine, stablecoin, helperConfig);
    }
}
