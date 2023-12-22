//contracts/organizer/ApprovalMatrix.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Modifiers.sol";

contract ApprovalMatrix is Modifiers {
  // Approval Matrix allows Orgs to define their approval matrix for deals and payouts
  // The approval matrix is a list of approval levels with the following properties:
  // 1. Each approval level has a minimum amount and a maximum amount
  // 2. Each approval level has a number of approvals required
  // 3. The approval matrix is sorted by minimum amount in ascending order
  //
  // Methods
  //
  //  Generate approval Matrix
  function _generateApprovalMatrix(
    uint256[] memory _minAmounts,
    uint256[] memory _maxAmounts,
    uint256[] memory _maxAggregatedAmount,
    uint8[] memory _approvalsRequired
  ) internal pure returns (ApprovalLevel[] memory) {
    // Check for empty arrays
    require(
      _maxAmounts.length > 0 &&
        _minAmounts.length > 0 &&
        _approvalsRequired.length > 0,
      "CS026"
    );

    // Check for equal length of arrays
    require(
      _minAmounts.length == _maxAmounts.length &&
        _minAmounts.length == _approvalsRequired.length,
      "CS020"
    );

    //  Generate empty Approval matrix
    ApprovalLevel[] memory approvalMatrix = new ApprovalLevel[](
      _minAmounts.length
    );

    //  Loop through the arrays and generate approval levels from params
    for (uint256 i = 0; i < _minAmounts.length; i++) {
      // Minimum amount should be less than maximum amount
      require(_minAmounts[i] < _maxAmounts[i], "CS021");

      // Minimum amount of current approval level should be equal to maximum amount of previous approval level
      if (i > 0) require(_minAmounts[i] == _maxAmounts[i - 1], "CS027");

      // Approvals required should be greater than 0
      require(_approvalsRequired[i] > 0, "CS022");

      approvalMatrix[i] = ApprovalLevel(
        _minAmounts[i],
        _maxAmounts[i],
        _maxAggregatedAmount[i],
        0,
        _approvalsRequired[i]
      );
    }

    return approvalMatrix;
  }

  // Set Approval Matrix on an org
  function setApprovalMatrix(
    address _safeAddress,
    address _tokenAddress,
    uint256[] memory _minAmounts,
    uint256[] memory _maxAmounts,
    uint256[] memory _maxAggregatedAmount,
    uint8[] memory _approvalsRequired
  ) public onlyOnboarded(_safeAddress) onlyApproverOrMultisig(_safeAddress) {
    // Approvals required has to be less than the number of approvers on dao
    for (uint256 i = 0; i < _approvalsRequired.length; i++) {
      require(
        _approvalsRequired[i] <= orgs[_safeAddress].approverCount,
        "CS029"
      );
    }

    //  Generate approval Matrix
    ApprovalLevel[] memory _approvalMatrix = _generateApprovalMatrix(
      _minAmounts,
      _maxAmounts,
      _maxAggregatedAmount,
      _approvalsRequired
    );

    // Loop because Copying of type struct memory[] to storage not yet supported
    for (uint256 i = 0; i < _approvalMatrix.length; i++) {
      // If the approval matrix already exists, update it
      if (
        orgs[_safeAddress].approvalMatrices[_tokenAddress].length > i &&
        orgs[_safeAddress].approvalMatrices[_tokenAddress][i].maxAmount > 0
      ) {
        orgs[_safeAddress].approvalMatrices[_tokenAddress][i] = _approvalMatrix[
          i
        ];
      } else {
        // If the approval matrix does not exist, add it
        orgs[_safeAddress].approvalMatrices[_tokenAddress].push(
          _approvalMatrix[i]
        );
      }
    }
  }

  // Bulk set Approval Matrices on an org
  function bulkSetApprovalMatrices(
    address _safeAddress,
    address[] memory _tokenAddresses,
    uint256[][] memory _minAmounts,
    uint256[][] memory _maxAmounts,
    uint256[][] memory _maxAggregatedAmount,
    uint8[][] memory _approvalsRequired
  ) public onlyOnboarded(_safeAddress) onlyApproverOrMultisig(_safeAddress) {
    // Check for equal length of arrays
    require(
      _tokenAddresses.length == _minAmounts.length &&
        _tokenAddresses.length == _maxAmounts.length &&
        _tokenAddresses.length == _approvalsRequired.length,
      "CS024"
    );

    // Loop through the arrays and generate approval levels from params
    for (uint256 i = 0; i < _tokenAddresses.length; i++) {
      setApprovalMatrix(
        _safeAddress,
        _tokenAddresses[i],
        _minAmounts[i],
        _maxAmounts[i],
        _maxAggregatedAmount[i],
        _approvalsRequired[i]
      );
    }
  }

  // Get Approval Matrix of org for a token
  function getApprovalMatrix(address _safeAddress, address _tokenAddress)
    external
    view
    returns (ApprovalLevel[] memory)
  {
    return orgs[_safeAddress].approvalMatrices[_tokenAddress];
  }

  //   Get Required Approval count for a payout
  function getRequiredApprovalCount(
    address _safeAddress,
    address _tokenAddress,
    uint256 _amount
  ) external view returns (uint256 requiredApprovalCount) {
    requiredApprovalCount = _getRequiredApprovalCount(
      _safeAddress,
      _tokenAddress,
      _amount
    );
    require(requiredApprovalCount > 0, "CS025");
  }

  function getAggregatedAmount(
    address _safeAddress,
    address _tokenAddress,
    uint256 _amount
  ) public view returns (uint256 requiredAggregatedAmount) {
    ApprovalLevel[] memory approvalMatrix = orgs[_safeAddress].approvalMatrices[
      _tokenAddress
    ];

    // Check if the approval matrix exists
    require(approvalMatrix.length > 0, "CS023");

    // Loop through the approval matrix and find the required approval count
    for (uint256 i = 0; i < approvalMatrix.length; i++) {
      if (
        _amount >= approvalMatrix[i].minAmount &&
        _amount <= approvalMatrix[i].maxAmount
      ) {
        requiredAggregatedAmount = approvalMatrix[i].maxAggregattedAmount;
        break;
      }
    }
  }

  function getCurrentSpendedAmount(
    address _safeAddress,
    address _tokenAddress,
    uint256 _amount
  ) public view returns (uint256 currentSpendedAmount) {
    ApprovalLevel[] memory approvalMatrix = orgs[_safeAddress].approvalMatrices[
      _tokenAddress
    ];

    // Check if the approval matrix exists
    require(approvalMatrix.length > 0, "CS023");

    // Loop through the approval matrix and find the required approval count
    for (uint256 i = 0; i < approvalMatrix.length; i++) {
      if (
        _amount >= approvalMatrix[i].minAmount &&
        _amount <= approvalMatrix[i].maxAmount
      ) {
        currentSpendedAmount = approvalMatrix[i].currentSpendedAmount;
        break;
      }
    }
  }

  //   Get Required Approval count for a payout
  function _getRequiredApprovalCount(
    address _safeAddress,
    address _tokenAddress,
    uint256 _amount
  ) internal view returns (uint256 requiredApprovalCount) {
    // Get the approval matrix for the token
    ApprovalLevel[] memory approvalMatrix = orgs[_safeAddress].approvalMatrices[
      _tokenAddress
    ];

    // Check if the approval matrix exists
    require(approvalMatrix.length > 0, "CS023");

    // Loop through the approval matrix and find the required approval count
    for (uint256 i = 0; i < approvalMatrix.length; i++) {
      if (
        _amount >= approvalMatrix[i].minAmount &&
        _amount <= approvalMatrix[i].maxAmount
      ) {
        requiredApprovalCount = approvalMatrix[i].approvalsRequired;
        break;
      }
    }
  }

  // Remove an approval matrix from an org
  function removeApprovalMatrix(address _safeAddress, address _tokenAddress)
    external
    onlyOnboarded(_safeAddress)
    onlyApproverOrMultisig(_safeAddress)
  {
    // Check if the approval matrix exists
    require(
      orgs[_safeAddress].approvalMatrices[_tokenAddress].length > 0,
      "CS023"
    );

    delete orgs[_safeAddress].approvalMatrices[_tokenAddress];
  }
}

