pragma solidity >=0.5.0;

interface IVaultTokenFactoryV2 {
    event VaultTokenCreated(
        uint256 indexed pid,
        address vaultToken,
        uint256 vaultTokenIndex
    );

    function optiSwap() external view returns (address);

    function router() external view returns (address);

    function masterChef() external view returns (address);

    function rewardsToken() external view returns (address);

    function reinvestFeeTo() external view returns (address);

    function getVaultToken(uint256) external view returns (address);

    function allVaultTokens(uint256) external view returns (address);

    function allVaultTokensLength() external view returns (uint256);

    function createVaultToken(uint256 pid)
        external
        returns (address vaultToken);
}

