// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.3) (proxy/transparent/ProxyAdmin.sol)

pragma solidity ^0.8.18;

import "./ERC1155Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./MerkleProof.sol";
import "./LayerZeroInterface.sol";

contract OmniNora is ERC1155Upgradeable, AccessControlUpgradeable, ERC1155SupplyUpgradeable, UUPSUpgradeable, ILayerZeroReceiver {
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant OWNER_ROLE = 0x00;

    uint public price;
    uint public bridgeFee;

    string public name;
    string public symbol;
    address public lzEndpoint;

    function initialize(string memory _name, string memory _symbol, uint _price, address _lzEndpoint) external initializer onlyProxy(){
        _grantRole(OWNER_ROLE, msg.sender);
        setName(_name);
        setEndpoint(_lzEndpoint);
        setSymbol(_symbol);
        setPrice(_price);
    }

    struct Collection{
        mapping (address => uint256) minted;
    }

    mapping (uint256 => address) dstAddresses;
    mapping (uint256 => bytes32) public roots;
    mapping (uint256 => Collection) collections;
    mapping (uint256 => string) public uris;
    bool public mintActive;

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setEndpoint(address _lzEndpoint) public onlyRole(OWNER_ROLE){
        lzEndpoint = _lzEndpoint;
    }

    function setMintActive() public onlyRole(OWNER_ROLE){
        mintActive = !mintActive;
    }

    function setupAddress(uint256 chainId, address dstAddress) public onlyRole(OWNER_ROLE){
        dstAddresses[chainId] = dstAddress;
    }

    function setRole(address admin, bytes32 role) public onlyRole(OWNER_ROLE){
        _grantRole(role, admin);
    }

    function setBridgeFee(uint256 _fee) public onlyRole(OWNER_ROLE){
        bridgeFee = _fee;
    }

    function setPrice(uint _price) public onlyRole(OWNER_ROLE){
        price = _price;
    }

    function setName(string memory _name) public onlyRole(OWNER_ROLE){
        name = _name;
    }

    function setSymbol(string memory _symbol) public onlyRole(OWNER_ROLE){
        symbol = _symbol;
    }

    function setRoot(bytes32 root, uint256 id) public onlyRole(ADMIN_ROLE){
        roots[id] = root;
    }

    function setURI(uint256 id, string memory _uri) public onlyRole(ADMIN_ROLE) {
       uris[id] = _uri;
    }

    function uri(uint256 tokenId) public override view returns(string memory){
        return uris[tokenId];
    }

    function ticketMint(uint256 amount) public payable onlyProxy(){
        require(mintActive == true, "Mint off");
        require(msg.value == price * amount, "Invalid price");
        _mint(msg.sender, 0, amount, '');
        collections[0].minted[msg.sender] += amount;
    }

    function specialMint(address account, uint256 id, uint256 amount, bytes32[] memory proof) public payable onlyProxy()
    {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(isValid(proof, leaf, id), "Not Allow");
        require(msg.value == price, "Invalid price");

        _mint(account, id, amount, '');
        collections[id].minted[msg.sender] += 1;
    }


    function bridge(uint256 id, uint256 amount, uint16 chainId) public payable onlyProxy()
    {
        bytes memory data = abi.encode(msg.sender, id, amount);
        (uint lzFee, ) = ILayerZeroEndpoint(lzEndpoint).estimateFees(chainId, dstAddresses[chainId], data, false, bytes(""));

        require(lzFee + bridgeFee <= msg.value, "Not enough value!");
        require(balanceOf(msg.sender, id) >= amount, "Not enough token balance!");
        require(dstAddresses[chainId] != address(0x0), "Not supported chain!");
        
        ILayerZeroEndpoint(lzEndpoint).send{value: (msg.value - bridgeFee)}(
            chainId,
            abi.encodePacked(dstAddresses[chainId], address(this)),
            data,
            payable(msg.sender),
            address(0x0),
            bytes("")
        );

        _burn(msg.sender, id, amount);
    }

    function lzReceive(uint16, bytes memory, uint64, bytes memory _payload) override external onlyProxy(){
        require(msg.sender == lzEndpoint, "Not authorized!");
        (address owner, uint256 id, uint256 amount) = abi.decode(_payload, (address, uint256, uint256));
        receiveNew(owner, id, amount);
    }

    function migrationDrop(address[] calldata recipients, uint256[] calldata amounts) public onlyRole(OWNER_ROLE){
        require(recipients.length == amounts.length, "Didnt match");
        for(uint i = 0; i < recipients.length; i++){
            _mint(recipients[i], 0, amounts[i], "");
        }
    }

    function receiveNew(address owner, uint256 id, uint256 amount) internal {
        _mint(owner, id, amount, "");
    }

    function isValid(bytes32[] memory proof, bytes32 leaf, uint256 id) internal view returns(bool) {
        return MerkleProof.verify(proof, roots[id], leaf);
    }

    function withdraw() external payable onlyRole(OWNER_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}
