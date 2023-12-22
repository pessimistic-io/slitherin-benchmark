//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ISignature.sol";
import "./IElleriumTokenERC20.sol";

/// ID `txnCount` has already been processed.
/// @param txnCount ID of the transaction.
error DuplicatedTransaction(uint256 txnCount);

/// Invalid signature.
error InvalidSignature(); 

/// @title Bridge for $ELM tokens. 
/// @author Wayne (Ellerian Prince)
/// @notice Allows $ELM to be bridged in/out of the off-chain server.
/// @dev This contract needs perms to mint $ELM. Used exclusively for $ELM.
contract ElleriaElmBridge is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /// @notice Number of past withdrawals.
  uint256 public withdrawCount;

  /// @notice Minimum withdrawal count (since this was migrated, to prevent overlapping IDs from before.)
  uint256 public minWithdrawCount;

  /// @notice Number of past deposits.
  uint256 public depositsCount;

  /// @notice Address used to verify signatures.
  address public signerAddr;

  /// @dev Reference to the contract that does signature verifications.
  ISignature public signatureAbi;

  /// @dev Address of the $ELM ERC20 Contract.
  address public elleriumAddr;

  // Prevents replaying of withdrawals.
  mapping(uint256 => bool) private _isProcessed; 
  

  /// @dev Initializes dependencies.
  /// @param _signatureAddr Address of contract used to verify signatures.
  /// @param _signerAddr Address of the private signer.
  /// @param _elmAddr Address of $ELM.
  /// @param _withdrawCount ID to start from.
  /// @param _depositsCount ID to start from.
  constructor(address _signatureAddr, address _signerAddr, address _elmAddr, 
  uint256 _withdrawCount, uint256 _depositsCount)
  {
      signatureAbi = ISignature(_signatureAddr);
      elleriumAddr = _elmAddr;
      signerAddr = _signerAddr;

      withdrawCount = _withdrawCount;
      minWithdrawCount = _withdrawCount;

      depositsCount = _depositsCount;
  }

  /// @notice Bridge $ELM into the game by burning it.
  /// @param _amountInWEI Amount to burn in WEI.
  function bridgeElleriumIntoGame(uint256 _amountInWEI) external nonReentrant {
    IERC20(elleriumAddr).safeTransferFrom(msg.sender, address(0), _amountInWEI);

    emit ERC20Deposit(msg.sender, elleriumAddr, _amountInWEI, ++depositsCount);
  }


    /// @notice Withdraw $ELM using a server-generated signature.
    /// @dev Withdrawals rely on signature and its payload; extra care must be taken in the private signature generation.
    ///      In the offchain server- Offchain $ELM balance is first deducted before the signature is generated to prevent stacking.
    ///      _txnCount is incremented every signature generation, and is checked for prevent replay attacks.
    ///      This means there can be gaps in _txnCount (but not withdrawCount).
    /// @param _amountInWEI Signature Payload.
    /// @param _txnCount Signature Payload.
  function retrieveElleriumFromGame(bytes memory _signature, uint256 _amountInWEI, uint256 _txnCount) external nonReentrant {
    if (_isProcessed[_txnCount] || _txnCount < minWithdrawCount) {
      revert DuplicatedTransaction(_txnCount);
    }

    if (!signatureAbi.verify(
      signerAddr, msg.sender, _amountInWEI, "retrieveElleriumFromGamev2", _txnCount, _signature
      )) {
      revert InvalidSignature();
    }

    ++withdrawCount;
    _isProcessed[_txnCount] = true;
    
    IElleriumTokenERC20(elleriumAddr).mint(msg.sender, _amountInWEI);

    emit ERC20Withdraw(msg.sender, elleriumAddr, _amountInWEI, _txnCount);
  }
  
  /// @notice Event emitted when BridgeElleriumIntoGame is called.
  /// @param sender The address of the caller.
  /// @param erc20Addr The address of the token deposited ($ELM).
  /// @param value The value of the deposit in WEI.
  /// @param transactionId The deposit ID.
  event ERC20Deposit(address indexed sender, address indexed erc20Addr, uint256 value, uint256 transactionId);

  /// @notice Event emitted when RetrieveElleriumFromGame is called.
  /// @param recipient The address of the caller and recipient.
  /// @param erc20Addr The address of the token retrieved ($ELM).
  /// @param value The value of the withdraw in WEI.
  /// @param transactionId The withdrawal ID.
  event ERC20Withdraw(address indexed recipient, address indexed erc20Addr, uint256 value, uint256 transactionId);
}
