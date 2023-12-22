// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IBinaryConfig {
    // solhint-disable-next-line
    function FEE_BASE() external view returns (uint256);

    function treasury() external view returns (address);

    function tradingFee() external view returns (uint256);

    function treasuryBips() external view returns (uint256);

    function maxVaultRiskBips() external view returns (uint256);

    function maxHourlyExposure() external view returns (uint256);

    function maxWithdrawalBipsForFutureBettingAvailable()
        external
        view
        returns (uint256);

    function binaryVaultImageTemplate() external view returns (string memory);

    function tokenLogo(address _token) external view returns (string memory);

    function vaultDescription() external view returns (string memory);

    function futureBettingTimeUpTo() external view returns (uint256);
}

