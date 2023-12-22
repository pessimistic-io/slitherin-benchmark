// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Ownable} from "./access_Ownable.sol";
import {FeeManager} from "./FeeManager.sol";

/// @title Station Network Fee Manager Contract
/// @author symmetry (@symmtry69), frog (@0xmcg), 👦🏻👦🏻.eth
/// @dev This contract enables payment by handling funds when charging base and variable fees on each Membership's mints
/// @notice The FeeController is intended to be inherited by all purchase modules to abstract all payment logic
/// and handle fees for every client's desired Membership implementation
abstract contract FeeController is Ownable {
    // using SafeERC20 for covering USDT no-return and other transfer issues
    using SafeERC20 for IERC20Metadata;

    /*============
        ERRORS
    ============*/

    error InvalidFee(uint256 expected, uint256 received);

    /*============
        EVENTS
    ============*/

    event FeePaid(
        address indexed collection,
        address indexed buyer,
        address indexed paymentToken,
        uint256 unitPrice,
        uint256 quantity,
        uint256 totalFee
    );
    event FeeWithdrawn(address indexed recipient, address indexed token, uint256 amount);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    /*=============
        STORAGE
    =============*/

    /// @dev Address of the deployed FeeManager contract which stores state for all collections' fee information
    /// @dev The FeeManager serves a Singleton role as central fee ledger for modules to read from
    address internal feeManager;

    /*==============
        SETTINGS
    ==============*/

    /// @param _newOwner The initialization of the contract's owner address, managed by Station
    /// @param _feeManager This chain's address for the FeeManager, Station's central fee management ledger
    constructor(address _newOwner, address _feeManager) {
        _transferOwnership(_newOwner);
        feeManager = _feeManager;
    }

    /// @dev Function to set a new FeeManager
    /// @param newFeeManager The new FeeManager address to write to storage
    function setNewFeeManager(address newFeeManager) external onlyOwner {
        require(newFeeManager != address(0) && newFeeManager != feeManager, "INVALID_FEE_MANAGER");
        emit FeeManagerUpdated(feeManager, newFeeManager);
        feeManager = newFeeManager;
    }

    /*==============
        WITHDRAW
    ==============*/

    /// @dev Function to withdraw the total balances of accrued base and variable eth fees collected from mints
    /// @dev Sends fees to the module's owner address, which is managed by Station Network
    /// @dev Access control enforced for tax implications
    /// @param paymentTokens The token addresses to call, where address(0) represents network token
    function withdrawFees(address[] calldata paymentTokens) external onlyOwner {
        address recipient = owner();
        for (uint256 i; i < paymentTokens.length; ++i) {
            uint256 amount;
            if (paymentTokens[i] == address(0)) {
                amount = address(this).balance;
                (bool success,) = recipient.call{value: amount}("");
                require(success);
            } else {
                amount = IERC20Metadata(paymentTokens[i]).balanceOf(address(this));
                IERC20Metadata(paymentTokens[i]).transfer(recipient, amount);
            }
            emit FeeWithdrawn(recipient, paymentTokens[i], amount);
        }
    }

    /*=============
        COLLECT
    =============*/

    /// @dev Function to collect fees for owner and collection in both network token and ERC20s
    /// @dev Called only by child contracts inheriting this one
    /// @param collection The token collection to mint from
    /// @param payoutAddress The address to send payment for the collection
    /// @param paymentToken The token address being used for payment
    /// @param recipient The recipient of successfully minted tokens
    /// @param quantity The number of items being minted, used to calculate the total fee payment required
    /// @param unitPrice The price per token to mint
    function _collectFeeAndForwardCollectionRevenue(
        address collection,
        address payoutAddress,
        address paymentToken,
        address recipient,
        uint256 quantity,
        uint256 unitPrice
    ) internal returns (uint256 paidFee) {
        // feeTotal is handled as either ETH or ERC20 stablecoin payment accordingly by FeeManager
        paidFee = FeeManager(feeManager).getFeeTotals(collection, paymentToken, recipient, quantity, unitPrice);
        uint256 total = quantity * unitPrice + paidFee;

        // for ETH context, accept funds only if the msg.value sent matches the FeeManager's calculation
        if (paymentToken == address(0x0)) {
            // collect fees- baseFee is still applied in FreeMintController context
            if (msg.value != total) revert InvalidFee(total, msg.value);

            // only perform external call + value to `payoutAddress` if called in GasCoinPurchaseController context
            if (unitPrice != 0) {
                // forward revenue to payoutAddress
                (bool success,) = payoutAddress.call{value: quantity * unitPrice}("");
                require(success, "PAYMENT_FAIL");
            }
        } else {
            // collect fees
            // transfer total to this contract first to update ERC20 approval storage
            // approval must have been made prior to top-level mint call
            IERC20Metadata(paymentToken).safeTransferFrom(msg.sender, address(this), total);
            // forward revenue to payoutAddress
            IERC20Metadata(paymentToken).safeTransfer(payoutAddress, quantity * unitPrice);
        }

        // emit event for accounting
        emit FeePaid(collection, recipient, paymentToken, unitPrice, quantity, paidFee);
    }
}

