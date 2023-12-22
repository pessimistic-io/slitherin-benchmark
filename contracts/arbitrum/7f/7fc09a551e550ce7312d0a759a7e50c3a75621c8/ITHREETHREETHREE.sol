pragma solidity ^0.8.10;

interface ITHREETHREETHREE {
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] amounts
    );
    event TransferSingle(
        address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount
    );
    event URI(string value, uint256 indexed id);

    function MAX_SUPPLY_PER_TOKEN() external view returns (uint256);
    function balanceOf(address, uint256) external view returns (uint256);
    function balanceOfBatch(address[] memory owners, uint256[] memory ids)
        external
        view
        returns (uint256[] memory balances);
    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) external;
    function burnSingle(address from, uint256 id, uint256 amount) external;
    function flipTokenMintActive(uint256 id) external;
    function isApprovedForAll(address, address) external view returns (bool);
    function mintBatch(uint256[] memory ids, uint256[] memory amounts) external payable;
    function mintSingle(uint256 id, uint256 amount) external payable;
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function receiptContract() external view returns (address);
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external;
    function setApprovalForAll(address operator, bool approved) external;
    function setReceiptContract(address _receiptContract) external;
    function setTokenName(uint256 id, string memory _name) external;
    function setURI(string memory newuri) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function tokens(uint256)
        external
        view
        returns (string memory name, uint256 currentSupply, uint256 etherPrice, bool mintActive);
    function transferOwnership(address newOwner) external;
    function uri(uint256) external view returns (string memory);
    function withdrawEther() external;
}

