// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./CommonErrors.sol";

abstract contract CommonConsts is CommonErrors {
    function setContractIdentifier(bytes32 identifier) internal {
        _CONTRACT_ID = identifier;
    }

    function CONTRACT_ID() external view returns (bytes32) {return _CONTRACT_ID;}

    modifier isContractIdentifier(address target, bytes32 identifier) {
        (bool success, bytes memory ret) = target.staticcall(
            abi.encodeWithSelector(
                CommonConsts.CONTRACT_ID.selector
            )
        );

        if (!success) revert ContractNoIdentifier(target);

        (bytes32 data) = abi.decode(ret, (bytes32));

        if (data != identifier) revert UnexpectedIdentifier(data, identifier);

        _;
    }

    bytes32 private _CONTRACT_ID;

    bytes32 internal constant MIDDLE_LAYER_IDENTIFIER = keccak256("contracts/middleLayer/MiddleLayer.sol");
    bytes32 internal constant ECC_IDENTIFIER = keccak256("contracts/ecc/ECC.sol");
    bytes32 internal constant LOAN_ASSET_IDENTIFIER = keccak256("contracts/satellite/loanAsset/LoanAsset.sol");
    bytes32 internal constant PTOKEN_IDENTIFIER = keccak256("contracts/satellite/pToken/PTokenBase.sol");
    bytes32 internal constant REQUEST_CONTROLLER_IDENTIFIER = keccak256("contracts/satellite/requestController/RequestController.sol");
}
