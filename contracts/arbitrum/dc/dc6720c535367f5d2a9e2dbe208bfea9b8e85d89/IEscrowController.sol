pragma solidity ^0.8.10;

interface IEscrowController {
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    function approve(address spender, uint256 id) external;
    function balanceOf(address owner) external view returns (uint256);
    function burn(uint256 id) external;
    function escrows(uint256) external view returns (address);
    function getApproved(uint256) external view returns (address);
    function isApprovedForAll(address, address) external view returns (bool);
    function mint(address to, address escrow) external returns (uint256);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function ownerOf(uint256 id) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 id) external;
    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) external;
    function setApprovalForAll(address operator, bool approved) external;
    function setRenderer(address r) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 id) external view returns (string memory);
    function transferFrom(address from, address to, uint256 id) external;
    function transferOwnership(address newOwner) external payable;
}


