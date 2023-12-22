// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

interface INLP {

    function getPositionOwned(address _owner) external view returns (uint256);
    function _deletePositionInfo(address _user) external;
    function mintNLP(address _sender, uint256 _tokenId) external;
    function burnNLP(uint256 _tokenId) external;
    function _addAmountToPosition(
        uint256 _mintedAmount,
        uint256 _collateralAmount,
        uint256 _LPAmount,
        uint256 _position) external;

    function _createPosition(
        address _owner,
        uint256 _id) external;

    function _topUpPosition(
        uint256 _mintedAmount,
        uint256 _collateralAmount,
        uint256 _LPAmount,
        uint256 _position,
        address _receiver) external;
}

