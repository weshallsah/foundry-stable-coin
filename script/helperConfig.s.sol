// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {ERC20Mock} from "../test/mocks/MockERC20.sol";
import {MockV3Agg} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    uint256 private constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 84532) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() internal view returns (NetworkConfig memory config) {
        config = NetworkConfig(
            0x694AA1769357215DE4FAC081bf1f309aDC325306,
            0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            vm.envUint("PRIVATE_KEY")
        );
    }

    function getAnvilEthConfig() internal returns (NetworkConfig memory config) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Agg ethpricefeed = new MockV3Agg(8, 2000e8);
        ERC20Mock ethtoken = new ERC20Mock("weth", "eth", msg.sender, 1000e8);

        MockV3Agg btcpricefeed = new MockV3Agg(8, 2000e8);
        ERC20Mock btctoken = new ERC20Mock("wbtc", "btc", msg.sender, 1000e8);
        vm.stopBroadcast();

        config = NetworkConfig(
            address(ethpricefeed),
            address(btcpricefeed),
            address(ethtoken),
            address(btctoken),
            DEFAULT_ANVIL_PRIVATE_KEY
        );
    }
}
