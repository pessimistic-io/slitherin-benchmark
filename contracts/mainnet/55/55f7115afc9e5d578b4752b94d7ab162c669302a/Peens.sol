//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./ERC2981.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./ERC721A.sol";

error SaleInactive();
error SoldOut();
error InvalidPrice();
error WithdrawFailed();
error InvalidQuantity();
error InvalidBatchMint();
error NotAChadHolder();
error AlreadyMinted();
error ContractMint();
error NotTheOwner();
error NotAllowed();
error BurnInactive();

contract Peens is ERC721A, Ownable, ERC2981 {
    uint256 public price = 0.0069 ether;
    uint256 public maxPerWallet = 400;
    uint256 public maxPerTransaction = 20;
    uint256 public chadMultiplier = 2;
    uint256 public honoraryMultiplier = 20;
    uint256 public supply = 16969;

    enum SaleState {CLOSED,OPEN}
    enum BurnState {CLOSED,OPEN}

    SaleState public saleState = SaleState.CLOSED;

    string public _baseTokenURI;

    mapping(address => uint256) private addressMintBalance;
    mapping(address => bool) private chadMintClaimed;

    uint public numPhases = 0;
    uint public currentIndex = 0;

    struct Phase {
        uint id;
        uint price;
        uint divider;
        SaleState saleState;
        BurnState burnState;
        mapping(address => uint256[]) burns;
        mapping(address => uint256) allowedMints;
        mapping(address => uint256[]) mints;
    }

    mapping(uint => Phase) public phases;
    address[] private withdrawAddresses;
    uint256[] private withdrawPercentages;

    constructor(
        string memory _name,
        string memory _symbol,
        uint96 _royaltyAmount,
        address _royaltyAddress
    ) ERC721A(_name, _symbol) {
        _setDefaultRoyalty(_royaltyAddress, _royaltyAmount);
    }

    event burnEvent(address _sender, uint[] tokens, uint phaseId);
    event mintEvent(address _sender, uint phaseId);

    function createPhase(uint _id, uint _price, uint _divider) external onlyOwner {
        Phase storage newPhase = phases[numPhases];
        numPhases++;
        newPhase.id = _id;
        newPhase.price = _price;
        newPhase.divider = _divider;
        newPhase.saleState = SaleState.CLOSED;
        newPhase.burnState = BurnState.CLOSED;
    }

    //// Minting

    modifier mintCompliance(uint256 qty) {
        if (msg.sender != tx.origin) revert ContractMint();
        if (saleState != SaleState.OPEN) revert SaleInactive();
        if (addressMintBalance[msg.sender] + qty > maxPerWallet) revert InvalidQuantity();
        if (currentIndex + (qty - 1) > supply) revert SoldOut();
        _;
    }

    function mint(uint256 qty) external payable mintCompliance(qty) {
        if (msg.value < price * qty) revert InvalidPrice();
        if (qty > maxPerTransaction) revert InvalidQuantity();
        completeMint(qty);
    }

    function chadMint(uint256 qty) external payable mintCompliance(qty) {
        uint balance = IERC721(0x8FA600364B93C53e0c71C7A33d2adE21f4351da3).balanceOf(msg.sender); //Chad
        uint balance2 = IERC721(0x8FA600364B93C53e0c71C7A33d2adE21f4351da3).balanceOf(msg.sender); //Honorary
        if (balance <= 0) revert NotAChadHolder();
        if (qty > ((balance * chadMultiplier) + (balance2 * honoraryMultiplier))) revert InvalidQuantity();
        if(chadMintClaimed[msg.sender]) revert AlreadyMinted();
        chadMintClaimed[msg.sender] = true;
        completeMint(qty);
    }

    function savePhaseMint(address adrs, uint phaseId, uint qty) private {
        for (uint i = _totalMinted(); i < _totalMinted() + qty; i++) {
            phases[phaseId].mints[adrs].push(i);
        }
    }

    function completeMint(uint256 qty) private {
        addressMintBalance[msg.sender] += qty;
        savePhaseMint(msg.sender, 0, qty);
        currentIndex += qty;
        _safeMint(msg.sender, qty);
    }

    function teamMint(uint256 qty, address recipient) external onlyOwner {
        if (currentIndex + (qty - 1) > supply) revert SoldOut();
        savePhaseMint(recipient, 0, qty);
        currentIndex += qty;
        _safeMint(recipient, qty);
    }

    function batchMint(uint64[] calldata qtys, address[] calldata recipients) external onlyOwner {
        uint256 numRecipients = recipients.length;
        if (numRecipients != qtys.length) revert InvalidBatchMint();

        for (uint256 i = 0; i < numRecipients; ) {
            if ((currentIndex - 1) + qtys[i] > supply) revert SoldOut();
            savePhaseMint(recipients[i], 0, qtys[i]);
            currentIndex += qtys[i];
            _safeMint(recipients[i], qtys[i]);

            unchecked {
                i++;
            }
        }
    }

    //// Phase

    modifier burnCompliance(uint[] calldata tokens) {
        for (uint i=0; i < tokens.length; i++) {
            if (ownerOf(tokens[i]) != msg.sender) revert NotTheOwner();
        }
        _;
    }

    function phaseBurn(uint[] calldata tokens, uint phaseId) public burnCompliance(tokens) {
        if (phases[phaseId].burnState == BurnState.CLOSED) revert BurnInactive();
        if (tokens.length % phases[phaseId].divider != 0) revert InvalidQuantity();
        for (uint i=0; i < tokens.length; i++) {
            phases[phaseId].burns[msg.sender].push(tokens[i]);
            _burn(tokens[i], true);
        }
        phases[phaseId].allowedMints[msg.sender] += tokens.length / phases[phaseId].divider;
        emit burnEvent(msg.sender, tokens, phaseId);
    }


    function phaseMint(uint phaseId, uint qty) external payable {
        if (phases[phaseId].saleState == SaleState.CLOSED) revert SaleInactive();
        if (phases[phaseId].burns[msg.sender].length <= 0) revert NotAllowed();
        if (msg.value < phases[phaseId].price * qty) revert InvalidPrice();
        uint allowed_qty = phases[phaseId].allowedMints[msg.sender];
        if (qty > allowed_qty) revert InvalidQuantity();
        for (uint i = _totalMinted() + 1; i <= _totalMinted() + qty; i++) {
            phases[phaseId].mints[msg.sender].push(i);
        }
        currentIndex += qty;
        _safeMint(msg.sender, qty);
        phases[phaseId].allowedMints[msg.sender] -= qty;
        emit mintEvent(msg.sender, phaseId);
    }

    //// main getters & setters

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
    }

    function setPerWalletMax(uint256 _val) external onlyOwner {
        maxPerWallet = _val;
    }

    function setPerTransactionMax(uint256 _val) external onlyOwner {
        maxPerTransaction = _val;
    }

    function setChadMultiplier(uint256 _val) external onlyOwner {
        chadMultiplier = _val;
    }

    function setHonoraryMultiplier(uint256 _val) external onlyOwner {
        honoraryMultiplier = _val;
    }

    function setSupply(uint256 newSupply) external onlyOwner {
        supply = newSupply;
    }

    function setSaleState(uint8 _state) external onlyOwner {
        saleState = SaleState(_state);
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function uri() public view returns (string memory) {
        return _baseTokenURI;
    }

    function getChadMintClaimed(address _adrs) public view returns(bool) {
        return chadMintClaimed[_adrs];
    }

    function getAddressMintBalance(address _adrs) public view returns(uint256) {
        return addressMintBalance[_adrs];
    }

    //// Phase getters & setters

    function getPhasePrice(uint _id) public view returns(uint) {
        return phases[_id].price;
    }

    function setPhasePrice(uint _id, uint _price) external onlyOwner {
        phases[_id].price = _price;
    }

    function getPhaseDivider(uint _id) public view returns(uint) {
        return phases[_id].divider;
    }

    function setPhaseDivider(uint _id, uint _divider) external onlyOwner {
        phases[_id].divider = _divider;
    }

    function getPhaseSaleState(uint _id) public view returns(SaleState) {
        return phases[_id].saleState;
    }

    function setPhaseSaleState(uint _id, SaleState _state) external onlyOwner {
        phases[_id].saleState = _state;
    }

    function getPhaseBurnState(uint _id) public view returns(BurnState) {
        return phases[_id].burnState;
    }

    function setPhaseBurnState(uint _id, BurnState _state) external onlyOwner {
        phases[_id].burnState = _state;
    }

    function getPhaseBurns(uint _id, address _adre) public view returns(uint256[] memory) {
        return phases[_id].burns[_adre];
    }

    function getPhaseAllowedMints(uint _id, address _adre) public view returns(uint256) {
        return phases[_id].allowedMints[_adre];
    }

    function getPhaseMints(uint _id, address _adre) public view returns(uint256[] memory) {
        return phases[_id].mints[_adre];
    }

    //// withdraws & royalities

    function _withdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        if (!success) revert WithdrawFailed();
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        for (uint256 i; i < withdrawAddresses.length; i++) {
            _withdraw(withdrawAddresses[i], (balance * withdrawPercentages[i]) / 100);
        }
    }

    function setRoyaltyInfo(address receiver, uint96 feeBasisPoints) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBasisPoints);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721A, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
