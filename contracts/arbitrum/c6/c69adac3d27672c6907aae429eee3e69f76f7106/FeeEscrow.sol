// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 } from "./ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { Vester } from "./Vester.sol";

uint256 constant TOTAL_BPS = 10_000;

/// @title FeeEscrow
/// @author Umami DAO
/// @notice Escrow contract that will hold deposit/withdraw fees and reimburse
///         GLP mint/burn fees, keeper gas fees and add the surplus to the vester
///         for vesting into the aggregate vault
contract FeeEscrow {
    using SafeTransferLib for ERC20;

    event ReimburseAndVest(uint256[5] feeAmounts, uint256[5] vestAmounts, uint256[5] keeperAmounts);

    ERC20[5] public ASSETS;
    address public immutable AGGREGATE_VAULT;
    Vester public immutable VESTER;

    constructor(ERC20[5] memory _assets, address _aggregateVault, address _vester) {
        ASSETS = _assets;
        AGGREGATE_VAULT = _aggregateVault;
        VESTER = Vester(_vester);
    }

    /**
     * @notice Reimburses the mint and burn fees, sends the surplus to the vester
     * @param _feeAmounts The amount of fees to reimburse
     * @param keeper The keeper address to send the keeper fees to
     * @param keeperBps The keeper share bps to send to the keeper
     */
    function pullFeesAndVest(uint256[5] memory _feeAmounts, address keeper, uint256 keeperBps)
        external
        onlyAggregateVault
    {
        require(keeperBps <= TOTAL_BPS, "FeeEscrow: keeperBps > TOTAL_BPS");
        uint256[5] memory reimbursedFeeAmounts;
        uint256[5] memory vestAmounts;
        uint256[5] memory keeperAmounts;

        for (uint256 i = 0; i < 5; i++) {
            uint256 balance = ASSETS[i].balanceOf(address(this));
            uint256 feeAmount = _feeAmounts[i] > balance ? balance : _feeAmounts[i];
            uint256 remainder = balance - feeAmount;
            uint256 toKeeper = remainder * keeperBps / TOTAL_BPS;
            uint256 toVest = remainder - toKeeper;

            reimbursedFeeAmounts[i] = feeAmount;
            vestAmounts[i] = toVest;
            keeperAmounts[i] = toKeeper;

            // reimburse the mint and burn fee
            if (feeAmount > 0) {
                ASSETS[i].safeTransfer(AGGREGATE_VAULT, feeAmount);
            }

            if (toKeeper > 0) {
                ASSETS[i].safeTransfer(keeper, toKeeper);
            }

            // send the surplus to vester for vesting into the vault
            if (toVest > 0) {
                ASSETS[i].safeApprove(address(VESTER), toVest);
                VESTER.addVest(address(ASSETS[i]), toVest);
            }
        }
    }

    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAggregateVault() {
        require(msg.sender == address(AGGREGATE_VAULT), "AssetVault: Caller is not AggregateVault");
        _;
    }
}

