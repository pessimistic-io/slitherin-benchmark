pragma solidity 0.8.18;

interface IEarthquake {
    function asset() external view returns (address asset);

    function deposit(uint256 pid, uint256 amount, address to) external;

    function depositETH(uint256 pid, address to) external payable;

    function epochs() external view returns (uint256[] memory);

    function epochs(uint256 i) external view returns (uint256);

    function epochsLength() external view returns (uint256);

    function getEpochsLength() external view returns (uint256);

    function idEpochBegin(uint256 id) external view returns (uint256);

    function idEpochEnded(uint256 id) external view returns (bool);

    function getVaults(uint256 pid) external view returns (address[2] memory);

    function emissionsToken() external view returns (address emissionsToken);

    function controller() external view returns (address controller);

    function treasury() external view returns (address treasury);

    function counterPartyVault() external view returns (address counterParty);

    function totalSupply(uint256 id) external view returns (uint256);

    function factory() external view returns (address factory);

    function withdraw(
        uint256 id,
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);

    function getEpochConfig(
        uint256
    ) external view returns (uint40, uint40, uint40);

    function getEpochDepositFee(
        uint256 id,
        uint256 assets
    ) external view returns (uint256, uint256);
}

