// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SeparatePool.sol";
import "./ISeparatePool.sol";
import "./ISeparatePoolFactory.sol";
import "./IChecker.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";

contract SeparatePoolFactory is ISeparatePoolFactory, Ownable {
    IChecker immutable checker;

    address public incomeMaker;

    // Addresses of NFTs with a pool
    address[] public allNfts;
    // NFT address to pool address
    mapping(address => address) public getPool;

    address public fur;

    constructor(address _incomeMaker, address _checker, address _fur) {
        incomeMaker = _incomeMaker;
        checker = IChecker(_checker);
        fur = _fur;
    }

    /**
     * @dev Get total number of NFTs with a separate pool
     */
    function numOfPools() external view returns (uint256 totalPools) {
        totalPools = allNfts.length;
    }

    /**
     * @dev Get addresses of nft collections that has a separate pool
     */
    function getAllNfts() external view returns (address[] memory nftsWithPool) {
        nftsWithPool = allNfts;
    }

    /**
     * @dev Get addresses of all separate pools
     */
    function getAllPools() external view returns (address[] memory poolAddresses) {
        uint256 length = allNfts.length;
        poolAddresses = new address[](length);

        for (uint256 i; i < length; ) {
            address nftAddress = allNfts[i];
            poolAddresses[i] = getPool[nftAddress];

            unchecked {
                ++i;
            }
        }

        return poolAddresses;
    }

    function getNftByPool(address _poolAddress) external view returns (address) {
        uint256 length = allNfts.length;
        for (uint256 i; i < length; ) {
            if (getPool[allNfts[i]] == _poolAddress) {
                return allNfts[i];
            }

            unchecked {
                ++i;
            }
        }

        return address(0);
    }

    /**
     * @dev Change owner for all separate pools
     */
    function transferOwnership(address _newOwner) public override onlyOwner {
        require(_newOwner != address(0), "Ownable: New owner is the zero address");

        _transferOwnership(_newOwner);

        uint256 length = allNfts.length;
        for (uint256 i; i < length; ) {
            ISeparatePool(getPool[allNfts[i]]).changeOwner(_newOwner);

            unchecked {
                ++i;
            }
        }
    }

    function setFur(address _newFur) external onlyOwner {
        fur = _newFur;
    }

    function setIncomeMaker(address _newIncomeMaker) external onlyOwner {
        incomeMaker = _newIncomeMaker;
    }

    /**
     * @dev Create pool and add address to array
     */
    function createPool(address _nftAddress) external returns (address poolAddress) {
        require(address(checker) != address(0), "SeparatePoolFactory: Checker not set.");
        require(_nftAddress != address(0), "SeparatePoolFactory: Zero address");
        require(getPool[_nftAddress] == address(0), "SeparatePoolFactory: Pool exists");

        (string memory tokenName, string memory tokenSymbol) = _tokenMetadata(_nftAddress);

        bytes32 _salt = keccak256(abi.encodePacked(_nftAddress));

        // New way to invoke create2 without assembly, parenthesis still needed for empty constructor
        poolAddress = address(
            new SeparatePool{ salt: _salt }(_nftAddress, owner(), tokenName, tokenSymbol)
        );

        allNfts.push(_nftAddress);
        getPool[_nftAddress] = poolAddress;
        checker.addToken(poolAddress);

        emit PoolCreated(_nftAddress, poolAddress, allNfts.length);
    }

    /**
     * @dev Get NFT name and symbol for token metadata
     */
    function _tokenMetadata(
        address _nftAddress
    ) private view returns (string memory tokenName, string memory tokenSymbol) {
        string memory nftName = IERC721Metadata(_nftAddress).name();
        string memory nftSymbol = IERC721Metadata(_nftAddress).symbol();
        tokenName = string.concat("Furion ", nftName);
        tokenSymbol = string.concat("F-", nftSymbol);

        return (tokenName, tokenSymbol);
    }
}
