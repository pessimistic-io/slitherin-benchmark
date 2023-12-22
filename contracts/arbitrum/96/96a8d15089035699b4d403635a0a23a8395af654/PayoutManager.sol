//contracts/Organizer.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ApprovalMatrix.sol";
import "./ApproverManager.sol";
import "./index.sol";
import "./Signature.sol";

/// @title Payout Manager for Organizer Contract
contract PayoutManager is ApprovalMatrix, ApproverManager, SignatureEIP712 {
  //
  //  Events
  //

  event PayoutValidated(
    address indexed safeAddress,
    uint256 indexed dealNonce,
    uint256 indexed payoutNonce,
    address[] operators,
    address recipient,
    address tokenAddress,
    uint256 amount
  );

  event ApprovalAdded(
    address indexed safeAddress,
    uint256 indexed dealNonce,
    uint256 indexed payoutNonce,
    address operators,
    address recipient,
    address tokenAddress,
    uint256 amount
  );

  event PayoutExecuted(
    address indexed safeAddress,
    uint256 indexed dealNonce,
    uint256 indexed payoutNonce,
    address claimaint,
    address tokenAddress,
    uint256 amount
  );

  event NonceInvalidate(address safeAdddress, uint256 indexed nonce);

  // Add approval to payout
  function addApproval(
    uint256 dealId,
    uint256 payoutNonce,
    uint96 amount,
    address tokenAddress,
    address recipient,
    address safeAddress,
    address approver
  ) internal {
    // Check if payout is already validated or executed
    if (
      payouts[payoutNonce].approvals[approver] ||
      payouts[payoutNonce].isExecuted
    ) {
      return;
    }

    if (
      (getCurrentSpendedAmount(safeAddress, tokenAddress, amount) + amount) >
      getAggregatedAmount(safeAddress, tokenAddress, amount)
    ) {
      revert("CS033");
    }

    payouts[payoutNonce].approvals[approver] = true;
    payouts[payoutNonce].approvalCount += 1;

    emit ApprovalAdded(
      safeAddress,
      dealId,
      payoutNonce,
      approver,
      recipient,
      tokenAddress,
      amount
    );

    // If approval count is greater than or equal to required approval count, validate payout
    if (
      payouts[payoutNonce].approvalCount >=
      _getRequiredApprovalCount(safeAddress, tokenAddress, amount)
    ) {
      payouts[payoutNonce].isValidated = true;

      emit PayoutValidated(
        safeAddress,
        dealId,
        payoutNonce,
        getApprovers(safeAddress),
        recipient,
        tokenAddress,
        amount
      );

      // If contributor has autoClaim disabled, make payout claimable
      // By default autoClaim will be false
      // 0 - Pay immediatly
      // 1 - addToClaimable
      if (orgs[safeAddress].autoClaim[recipient]) {
        orgs[safeAddress].claimables[tokenAddress][recipient] += amount;
      } else {
        // If contributor has autoClaim enabled, execute payout
        bytes memory signature = bytes("");

        executePayout(
          safeAddress,
          tokenAddress,
          dealId,
          payoutNonce,
          recipient,
          amount,
          signature
        );

        // Mark payout as executed
        payouts[payoutNonce].isExecuted = true;
      }
    }
  }

  function cancelNonce(
    uint256 nonce,
    address safeAddress,
    bytes memory signature
  ) external {
    require(safeAddress != address(0), "CS004");

    address signer = validateCancelNonceSignature(
      nonce,
      safeAddress,
      signature
    );

    require(signer == MASTER_OPERATOR, "CS032");
    payouts[nonce].isExecuted = true;
    emit NonceInvalidate(safeAddress, nonce);
  }

  // Validate single payout
  function validateSinglePayout(
    uint256 _dealId,
    uint256 _payoutNonce,
    uint96 _amount,
    address _tokenAddress,
    address _recipient,
    uint256 _networkId,
    address _safeAddress,
    address[] memory _approvers,
    bytes[] memory _signatures
  ) external {
    // Validate signatures for each approver
    for (uint96 i = 0; i < _signatures.length; i++) {
      address _signer = validateSingleDealSignature(
        _approvers[i],
        _dealId,
        _payoutNonce,
        _amount,
        _tokenAddress,
        _recipient,
        _networkId,
        _safeAddress,
        _signatures[i]
      );

      // Signature should be from one of the approvers
      require(isApprover(_safeAddress, _signer), "CS031");

      // Add approval
      addApproval(
        _dealId,
        _payoutNonce,
        _amount,
        _tokenAddress,
        _recipient,
        _safeAddress,
        _signer
      );
    }
  }

  // Validate multiple payouts in a single signature
  function validateBulkPayout(
    uint256[] memory _dealIds,
    uint256[] memory _payoutNonces,
    uint96[] memory _amounts,
    address[] memory _tokenAddresses,
    address[] memory _recipients,
    uint256[] memory _networkIds,
    address[] memory _safeAddresses,
    address _approver,
    uint256[] memory whitelistNonce,
    bytes memory _signature
  ) external {
    // Length of all arrays should be same
    require(
      _dealIds.length == _payoutNonces.length &&
        _payoutNonces.length == _amounts.length &&
        _amounts.length == _tokenAddresses.length &&
        _tokenAddresses.length == _recipients.length &&
        _recipients.length == _safeAddresses.length &&
        _safeAddresses.length == _networkIds.length,
      "CS020"
    );

    // Validate signature
    address _signer = validateBulkDealSignature(
      _approver,
      _dealIds,
      _payoutNonces,
      _amounts,
      _tokenAddresses,
      _recipients,
      _networkIds,
      _safeAddresses,
      _signature
    );

    for (uint96 i = 0; i < whitelistNonce.length; i++) {}

    // Add approval for each payout
    for (uint256 index = 0; index < _dealIds.length; index++) {
      if (!checkWhitelist(_payoutNonces[index], whitelistNonce)) {
        continue;
      }

      // Signature should be from one of the approvers
      require(isApprover(_safeAddresses[index], _signer), "CS031");
      addApproval(
        _dealIds[index],
        _payoutNonces[index],
        _amounts[index],
        _tokenAddresses[index],
        _recipients[index],
        _safeAddresses[index],
        _approver
      );
    }
  }

  // Function for Contributors to enable or disable auto Claiming
  // For a particular safeAddress
  function modifyAutoClaim(address _safeAddress, bool _enabled)
    external
    onlyOnboarded(_safeAddress)
  {
    require(_safeAddress != address(0), "CS004");
    orgs[_safeAddress].autoClaim[msg.sender] = _enabled;
  }

  function checkWhitelist(uint256 nonce, uint256[] memory whitelist)
    internal
    pure
    returns (bool)
  {
    for (uint256 index = 0; index < whitelist.length; index++) {
      if (whitelist[index] == nonce) {
        return true;
      }
    }

    return false;
  }

  // Execute payout
  function executePayout(
    address _safeAddress,
    address _tokenAddress,
    uint256 _dealId,
    uint256 _payoutNonce,
    address _reciever,
    uint96 amount,
    bytes memory _signature
  ) internal {
    // Payout should be validated
    require(payouts[_payoutNonce].isValidated, "CS030");

    AlowanceModule allowance = AlowanceModule(ALLOWANCE_MODULE);

    address payable to = payable(_reciever);

    // Execute payout via allowance module
    allowance.executeAllowanceTransfer(
      GnosisSafe(_safeAddress),
      _tokenAddress,
      to,
      amount,
      0x0000000000000000000000000000000000000000,
      0,
      address(this),
      _signature
    );

    emit PayoutExecuted(
      _safeAddress,
      _dealId,
      _payoutNonce,
      to,
      _tokenAddress,
      amount
    );
  }
}

