// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

interface IStakeManager {
    function stakePABOnService(
        uint256 tokenId,
        address service,
        address owner
    ) external;

    function isStaked(uint256 tokenId, address service)
        external
        view
        returns (bool);

    function unstakePeekABoo(uint256 tokenId) external;

    function getServices() external view returns (address[] memory);

    function isService(address service) external view returns (bool);

    function initializeEnergy(uint256 tokenId) external;

    function claimEnergy(uint256 tokenId) external;

    function useEnergy(uint256 tokenId, uint256 amount) external;

    function ownerOf(uint256 tokenId) external returns (address);

    function tokensOf(address owner) external returns (uint256[] memory);
}

