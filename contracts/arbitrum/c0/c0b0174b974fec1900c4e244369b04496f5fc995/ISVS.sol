// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title ISVS
 * @author Souq.Finance
 * @notice Interface for SVS contract
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

interface ISVS {
    event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _value);
    event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _values);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    event URI(string _value, uint256 indexed _id);

    function balanceOf(address _owner, uint256 _id) external view returns (uint256);

    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids) external view returns (uint256[] memory);

    function setApprovalForAll(address _operator, bool _approved) external;

    function isApprovedForAll(address _owner, address _operator) external view returns (bool);

    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external;

    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external;

    function mint(address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;

    function burn(address _account, uint256 _id, uint256 _amount) external;

    function currentTranche() external view returns (uint256);

    function totalSupplyPerTranche(uint256 _tranche) external view returns (uint256);

    function setTokenTrancheTimestamps(uint256 _tokenId, uint256 _timestamps) external;

    function tokenTranche(uint256 _tokenId) external view returns (uint256);
}

