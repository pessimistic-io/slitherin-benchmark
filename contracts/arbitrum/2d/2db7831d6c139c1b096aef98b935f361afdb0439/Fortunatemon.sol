// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./SignatureLens.sol";

contract Fortunatemon is ERC721Enumerable, ReentrancyGuard, Pausable, SignatureLens{
    using SafeMath for uint256;
    using Strings for uint256;
    using Counters for Counters.Counter;

    enum Phase {
        AIRDROP,
        FIRST_SALE,
        SECOND_SALE
    }

    uint private immutable _cap;
    uint private immutable _airdropCap;
    uint private immutable _firstSaleCap;

    Phase private _phase;
    uint private _perSaleCap;
    uint private _fee;
    address private _feeTo;
    string private _tokenBaseURI;
    mapping(address => bool) private _userAirdropped;
    mapping(Phase => uint) private _phaseMined;

    Counters.Counter private _tokenIdTracker;

    event PaymentReceived(address indexed sender,uint amount);
    event ResetFee(address indexed operator, uint oldFee, uint newFee);
    event ResetFeeTo(address indexed operator, address indexed oldFeeTo, address indexed newFeeTo);
    event ResetPhase(address indexed operator, Phase oldPhase, Phase newPhase);
    event ResetTokenBaseURI(address indexed operator, address indexed oldTokenBaseURI, address indexed newTokenBaseURI);
    event Airdrop(address indexed operator,uint count);
    event BatchSale(address indexed operator,uint count,uint cost);

    constructor(uint cap, uint airdropCap, uint firstSaleCap, uint perSaleCap, uint fee, address feeTo, address signer, string memory tokenBaseURI) ERC721("Fortuna NFT", "FAT") SignatureLens(signer){
        require(feeTo != address(0)
            && cap >0
            && (airdropCap >0 && airdropCap <= cap)
            && (firstSaleCap >0 && firstSaleCap <= cap)
            && (perSaleCap >0 && perSaleCap <= cap),"Parameter error");
        _cap = cap;
        _airdropCap = airdropCap;
        _firstSaleCap = firstSaleCap;
        _perSaleCap = perSaleCap;
        _fee = fee;
        _feeTo = feeTo;
        _tokenBaseURI = tokenBaseURI;
        _phase = Phase.FIRST_SALE;

        _pause();
    }

    function resetFee(uint fee) external onlyOwner{
        uint oldFee = _fee;
        _fee = fee;
        emit ResetFee(_msgSender(), oldFee, fee);
    }

    function resetFeeTo(address feeTo) external onlyOwner{
        address oldFeeTo = _feeTo;
        _feeTo = feeTo;
        emit ResetFeeTo(_msgSender(), oldFeeTo, feeTo);
    }

    function resetPhase(Phase phase) external onlyOwner{
        Phase oldPhase = _phase;
        _phase = phase;

        emit ResetPhase(_msgSender(), oldPhase, phase);
    }

    function resetPause(bool pause) external onlyOwner{
        pause ? _pause() : _unpause();
    }

    function cap() public view returns(uint){
        return _cap;
    }

    function airdropCap() public view returns(uint){
        return _airdropCap;
    }

    function firstSaleCap() public view returns(uint){
        return _firstSaleCap;
    }

    function perSaleCap() public view returns(uint){
        return _perSaleCap;
    }

    function phase() public view returns(Phase){
        return _phase;
    }

    function fee() public view returns(uint){
        return _fee;
    }

    function feeTo() public view returns(address){
        return _feeTo;
    }

    function tokenBaseURI() public view returns(string memory){
        return _tokenBaseURI;
    }

    function userAirdropped(address user) public view returns(bool){
        return _userAirdropped[user];
    }

    function phaseMined(Phase phase) public view returns(uint){
        return _phaseMined[phase];
    }

    function airdrop(Signature calldata signature) external nonReentrant{
        require(phaseMined(Phase.AIRDROP).add(1) <= airdropCap(),"The maximum number of drops has been exceeded");
        require(!userAirdropped(msg.sender), "The airdrop has been received");
        require(verifySignature("Airdrop(Signature)", signature), "Illegal operation");

        batchMint(1);
        _phaseMined[Phase.AIRDROP] = _phaseMined[Phase.AIRDROP].add(1);
        _userAirdropped[msg.sender] = true;

        emit Airdrop(msg.sender,1);
    }

    function batchSale(uint count) external payable nonReentrant whenNotPaused{
        uint perSaleable = perSaleable();
        require(count >0 && count <= perSaleable ,"Illegal sale quantity");
        require(msg.value >= fee().mul(count), "The ether value sent is not correct");
        payable(feeTo()).transfer(msg.value);

        batchMint(count);
        Phase phase = phase();
        _phaseMined[phase] = _phaseMined[phase].add(count);

        emit BatchSale(msg.sender, count, msg.value);
    }

    function batchMint(uint count) internal{
        for(uint i=0; i< count; i++){
            _tokenIdTracker.increment();
            _safeMint(_msgSender(), _tokenIdTracker.current());
        }

        require(totalSupply() <= cap(),"Exceed the maximum mint quantity");
    }

    function perSaleable() public view returns(uint){
        uint minted = totalSupply();
        if(minted >= cap()){
            return 0;
        }

        uint diff = 0;
        if(phase() == Phase.FIRST_SALE){
            uint phaseMined = phaseMined(phase());
            diff = firstSaleCap().sub(phaseMined);
        }else{
            diff = cap().sub(minted);
        }
        return diff > perSaleCap() ? perSaleCap() : diff;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return bytes(_tokenBaseURI).length > 0 ? string(abi.encodePacked(_tokenBaseURI, tokenId.toString())) : "";
    }

    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }
}
