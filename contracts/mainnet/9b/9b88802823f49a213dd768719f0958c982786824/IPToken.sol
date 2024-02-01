// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./INftController.sol";

interface IPToken {

    /**
     * @notice NFT staking info
     * @member startBlock The block height when exchanging NFT for ptoken
     * @member endBlock Endning block height of staking deadline
     * @member userAddr User address
     * @member action The method of staking NFT - can either be exchanged or redeemed
     */
    struct NftInfo {
        uint256 startBlock;
        uint256 endBlock;
        address userAddr;
        INftController.Action action;
    }

    /// @notice Emitted when swap random NFT
    event RandomTrade(address indexed recipient, uint256 nftIdCount, uint256 totalFee, uint256[] nftIds);

    /// @notice Emitted when swap specific NFT
    event SpecificTrade(address indexed recipient, uint256 nftIdCount, uint256 totalFee, uint256[] nftIds);

    /// @notice Emitted when swap ptoken or deposit NFT
    event Deposit(address indexed operator, uint256[] nftIds, uint256 blockNumber);

    /// @notice Emitted when withdraw deposited (locked) NFT
    event Withdraw(address indexed operator, uint256[] nftIds);

    /// @notice Emitted when leveraged NFT is liquidated - status changed to exchangeable
    event Convert(address indexed operator, uint256[] nfts);

    /*** User Interface ***/
    function factory() external view returns(address);
    function nftAddress() external view returns(address);
    function pieceCount() external view returns(uint256);
    function DOMAIN_SEPARATOR() external view returns(bytes32);
    function nonces(address) external view returns(uint256);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function randomTrade(uint256 nftIdCount) external returns(uint256[] memory nftIds);
    function specificTrade(uint256[] memory nftIds) external;
    function deposit(uint256[] memory nftIds) external returns(uint256 tokenAmount);
    function deposit(uint256[] memory nftIds, uint256 blockNumber) external returns(uint256 tokenAmount);
    function withdraw(uint256[] memory nftIds) external returns(uint256 tokenAmount);
    function convert(uint256[] memory nftIds) external;
    function getRandNftCount() external view returns(uint256);
    function getNftInfo(uint256 nftId) external view returns (NftInfo memory);
    function getRandNft(uint256 _tokenIndex) external view returns (uint256);
    function getNftController() external view returns(INftController);
}

