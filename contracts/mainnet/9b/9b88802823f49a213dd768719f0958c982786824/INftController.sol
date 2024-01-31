// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface INftController {

    /**
     * @notice Ptoken <> NFT configuration
     * @member randFeeRate The fee rate for exchanging ptoken for random nft
     * @member noRandFeeRate The fee rate for exchanging ptoken for specific nft
     */
    struct ConfigInfo {
        uint256 randFeeRate;
        uint256 noRandFeeRate;
    }

    /**
     * @notice NFT staking status
     * @member FREEDOM Free state - can be exchanged by ptoken
     * @member STAKING Staked state - can only be redeemed until duration ends
     */
    enum Action { FREEDOM, STAKING }

    /*** User Interface ***/
    function STAKER_ROLE() external view returns(bytes32);
    function pieceCount() external view returns(uint256);
    function randomTool() external view returns(address);
    function openControl() external view returns(bool);
    function whitelist(address) external view returns(bool);
    function nftBlackList(address) external view returns(bool);
    function nftIdBlackList(address, uint256) external view returns(bool);
    function configInfo() external view returns (uint256 randFeeRate, uint256 noRandFeeRate);
    function enableConfig(address nftAddr) external view returns(bool);
    function nftConfigInfo(address nftAddr) external view returns (uint256 randFeeRate, uint256 noRandFeeRate);
    function getFeeInfo(address nftAddr) external view returns(uint256 randFee, uint256 noRandFee);
    function getRandoms(address nftAddr, uint256 rangeMaximum) external returns(uint256);
    function supportedNft(address nftAddr) external view returns(bool);
    function supportedNftId(address operator, address nftAddr, uint256 nftId, Action action) external view returns(bool);

    /*** Admin Functions ***/
    function updateRandomTool(address _randomTool) external;
    function updateConfigInfo(ConfigInfo memory configInfo_) external;
    function updateNftConfigInfo(address nftAddr, ConfigInfo memory nftConfigInfo_) external;
    function setNftBlackList(address nftAddr, bool harmful) external;
    function setNftIdBlackList(address nftAddr, uint256 nftId, bool harmful) external;
    function batchSetNftIdBlackList(address nftAddr, uint256[] calldata nftIds, bool harmful) external;
    function setOpenControl(bool newOpenControl) external;
    function setWhitelist(address nftAddr, bool isAllow) external;
    function batchSetWhitelist(address[] calldata nftAddrs, bool isAllow) external;    
}
