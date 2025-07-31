// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {IDSCEngine} from "./interfaces/IDSCEngine.sol";

/**
 * @title DSC Engine
 * @author Lyes-Boudjabout
 * This system is designed to be as minimal as possible, and have the tokens maintain a 1 token = 1$ peg
 * This stablecoin has the following properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * @notice This contract is the core of the DSC System, it handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is IDSCEngine {
    function depositCollateralAndMintDsc() external override {}

    function redeemCollateralForDsc() external override {}

    function burnDsc() external override {}

    function liquidate() external override {}

    function getHealthFactor() external view override {}
}
