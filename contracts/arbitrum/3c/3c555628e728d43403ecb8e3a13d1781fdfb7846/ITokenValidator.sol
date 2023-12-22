// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IDistToken.sol";

interface ITokenValidator {
    function addDistToken(IDistToken) external;
    function addSingleToken(address) external;
    function addTokenPair(address, address) external;
    function removeDistToken(IDistToken) external;
    function removeToken(address) external;
    function enableValidation() external;
    function disableValidation() external;
    function isAllowedDistToken(address) external view returns (bool);
    function isAllowedValueToken(address) external view returns (bool);
    function isAllowedToken(address) external view returns (bool);
}

