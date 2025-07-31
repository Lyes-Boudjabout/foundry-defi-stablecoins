// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDecentralizedStableCoin is Script {
    DecentralizedStableCoin decentralizedStableCoin;

    function run(address deployer) public returns (DecentralizedStableCoin) {
        vm.startBroadcast(deployer);
        decentralizedStableCoin = new DecentralizedStableCoin();
        vm.stopBroadcast();
        return decentralizedStableCoin;
    }
}
