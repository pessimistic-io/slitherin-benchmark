// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { AccessControl } from "./AccessControl.sol";
import { IPepeBet } from "./IPepeBet.sol";

contract PepeOracle is AccessControl {
    bytes32 public constant PEPE_ORACLE_ADMIN = keccak256("PEPE_ORACLE_ADMIN");
    bytes32 public constant PEPE_EXTERNAL_ORACLE = keccak256("PEPE_EXTERNAL_ORACLE");

    address public pepeBetAddress;

    struct CloseBetParams {
        uint256 betId;
        uint256 closePrice;
    }

    event BetSettlementError(uint256 indexed betId, uint256 closePrice, string reason);
    event PepeBetAddressUpdated(address indexed oldPepeBet, address indexed newPepeBet);

    error InvalidAddress();

    constructor(address _oracle) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PEPE_ORACLE_ADMIN, msg.sender);
        _grantRole(PEPE_EXTERNAL_ORACLE, _oracle);
    }

    function updatePepeBetAddress(address _pepeBet) external onlyRole(PEPE_ORACLE_ADMIN) {
        if (_pepeBet == address(0)) revert InvalidAddress();
        address oldPepeBet = pepeBetAddress;
        pepeBetAddress = _pepeBet;
        emit PepeBetAddressUpdated(oldPepeBet, _pepeBet);
    }

    function settleBets(CloseBetParams[] calldata closeBetParams) external onlyRole(PEPE_EXTERNAL_ORACLE) {
        uint256 ordersLength = closeBetParams.length;

        for (uint256 i = 0; i < ordersLength; ) {
            uint256 betBetId = closeBetParams[i].betId;
            uint256 betClosePrice = closeBetParams[i].closePrice;

            try IPepeBet(pepeBetAddress).settleBet(betBetId, betClosePrice) {} catch Error(string memory reason) {
                emit BetSettlementError(betBetId, betClosePrice, reason);
            }
            unchecked {
                ++i;
            }
        }
    }
}

