// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

import "./IERC721Details.sol";

interface IKEIReferrals {
    event Register(address indexed account, address indexed referrer, address indexed sender);

    function REGISTER_ROLE() external pure returns (bytes32);

    function MANAGE_ROLE() external pure returns (bytes32);

    function updateSellerFee(uint256 newSellerFee) external;

    function updateDetails(IERC721Details.ContractDetails calldata newContractDetails) external;

    function updateDescriptor(address newDescriptor) external;

    function updateFeeReceiver(address newAssetReceiver) external;

    function register(address account, address referrer) external returns (bool);

    function registerOrigin(address referrer) external returns (bool);

    function registerSender(address referrer, bytes calldata forwardCall) external payable returns (bool result);

    function referrerOf(address account) external view returns (address);

    function listReferrersOf(address account, uint256 depth) external view returns (address[] memory referrers);
}

