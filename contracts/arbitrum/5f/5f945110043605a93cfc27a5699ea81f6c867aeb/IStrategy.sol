// SPDX-License-Identifier: MIT

interface IStrategy {
    function reinvest() external;

    function ADMIN_FEE_BIPS() external view returns (uint256);

    function WITHDRAW_FEE_BIPS() external view returns (uint256);

    function REINVEST_FEE_BIPS() external view returns (uint256);

    function feeRecipient() external view returns (address);

    function setAdminFeeBips(uint256 newBips) external;

    function setWithdrawFeeBips(uint256 newBips) external;

    function setReinvestFeeBips(uint256 newBips) external;

    function setFeeRecipient(address newRecipient) external;

}

