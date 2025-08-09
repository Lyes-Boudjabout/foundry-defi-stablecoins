// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";

contract DecentralizedStableCoinTest is Test {
    error OwnableUnauthorizedAccount(address sender);

    DeployDecentralizedStableCoin public deployDecentralizedStableCoin;
    DecentralizedStableCoin public decentralizedStableCoin;
    DSCEngine public dscEngine;
    address public user;
    address public user1;
    uint256 private constant INITIAL_BALANCE = 10 ether;

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        user = makeAddr("user");
        user1 = makeAddr("user1");
        vm.deal(user, INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        (decentralizedStableCoin, dscEngine) = deployDecentralizedStableCoin.run();
    }

    function testDeployedCoinName() public view {
        string memory expectedOutput = "DecentralizedStableCoin";
        string memory actualOutput = decentralizedStableCoin.name();
        assertEq(keccak256(abi.encodePacked(expectedOutput)), keccak256(abi.encodePacked(actualOutput)));
    }

    function testDeployedCoinSymbol() public view {
        string memory expectedOutput = "DSC";
        string memory actualOutput = decentralizedStableCoin.symbol();
        assertEq(keccak256(abi.encodePacked(expectedOutput)), keccak256(abi.encodePacked(actualOutput)));
    }

    function testOwnerAddress() public view {
        address owner = decentralizedStableCoin.owner();
        assertEq(owner, address(dscEngine));
    }

    function testMintingOnlyByOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));
        decentralizedStableCoin.mint(user1, 100);

        vm.prank(address(dscEngine));
        bool success = decentralizedStableCoin.mint(user1, 100);
        assertEq(success, true);
    }
}
