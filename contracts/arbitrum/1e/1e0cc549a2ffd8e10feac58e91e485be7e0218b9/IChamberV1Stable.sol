// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;

interface IChamberV1Stable {
    function burn(uint256 _shares) external;

    function mint(uint256 usdAmount) external;

    function calculateCurrentPoolReserves()
        external
        view
        returns (uint256, uint256);

    function currentLTV() external view returns (uint256);

    function currentUSDBalance() external view returns (uint256);

    function getAdminBalance() external view returns (uint256, uint256);

    function get_i_aaveVToken() external view returns (address);

    function get_i_aaveAUSDToken() external view returns (address);

    function get_s_totalShares() external view returns (uint256);

    function get_s_userShares(address user) external view returns (uint256);

    function _redeemFees() external;

    function setTicksRange(int24 _ticksRange) external;

    function giveApprove(address _token, address _to) external;

    function setLTV(
        uint256 _targetLTV,
        uint256 _minLTV,
        uint256 _maxLTV,
        uint256 _hedgeDev
    ) external;
}

