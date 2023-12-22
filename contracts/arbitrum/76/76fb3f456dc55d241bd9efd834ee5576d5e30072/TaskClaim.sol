pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./ECDSA.sol";
import "./EIP712.sol";
import "./ISecondLiveEditor.sol";

/**
 * @title AirdropClaim
 * @author SecondLive Protocol
 *
 * Campaign contract 
    that allows privileged DAOs to initiate campaigns for members to 
    claim SecondLiveNFTs.
 */
contract AirdropClaim is EIP712, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    bool private initialized;
    ISecondLiveEditor public editorNFT;
    address public signer;

    uint private seed;
    mapping(uint256 => bool) public isClaimed;
    mapping(address => bool) public userClaimed;
    uint256 public numClaimed;

    struct Suit {
        uint256[][] singles; // == Attribute[]
    }
    Suit[] private suits;

    // random index
    EnumerableSet.UintSet private suitTypeSet;

    uint256 public startTime;
    uint256 public endTime;

    event UpdateSigner(address signer);
    event UpdateTime(uint256 _startTime, uint256 _endTime);
    event EventClaim(uint256 _nftID, uint256 _dummyId, address _mintTo);

    constructor() EIP712("SecondLive", "1.0.0") {}

    // _attributes
    // [[[1,2,3,4],[5,6,7,8],[3,5,3,1]],
    // [[11,12,13,4],[15,16,17,8],[13,15,13,1]],
    // [[21,32,23,4],[45,56,37,8],[43,55,36,1]]]
    function initialize(
        address _owner,
        address _signer,
        ISecondLiveEditor _editorNFT,
        uint256 _startTime,
        uint256 _endTime,
        uint256[][][] memory _attributes) external {

        require(!initialized, "initialize: Already initialized!");
        
        eip712Initialize("SecondLive", "1.0.0");
        _transferOwnership(_owner);
        signer = _signer;
        editorNFT = _editorNFT;
        startTime = _startTime;
        endTime = _endTime;
        for (uint i = 0; i < _attributes.length; i++) {
            suitTypeSet.add(i);
            uint256[][] memory attribute = _attributes[i];
            suits.push(Suit({singles: attribute}));
        }
        initialized = true;
    }

    function claimHash(
        uint256 _dummyId,
        address _to
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Claim(uint256 dummyId,address mintTo)"),
                        _dummyId,
                        _to
                    )
                )
            );
    }

    function verifySignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signer;
    }

    function setSinger(address _signer) external onlyOwner {
        signer = _signer;
        emit UpdateSigner(_signer);
    }

    function claim(
        uint256 _dummyId,
        address _mintTo,
        bytes calldata _signature
    ) external nonReentrant {
        require(block.timestamp >= startTime, "not start");
        require(block.timestamp <= endTime, "have end");
        require(_mintTo == msg.sender, "_mintTo is not equal sender");
        require(!isClaimed[_dummyId], "Already Claimed!");
        require(!userClaimed[_mintTo], "have claim");
        require(
            verifySignature(claimHash(_dummyId, _mintTo), _signature),
            "Invalid signature"
        );
        seed = uint(keccak256(abi.encodePacked(seed, _mintTo)));
        uint seedBase = suitTypeSet.length();
        uint index = seed % seedBase;
        uint suitId = suitTypeSet.at(index);
        Suit memory suit_ = suits[suitId];
        uint256[][] memory singles = suit_.singles;

        for (uint256 i = 0; i < singles.length; i++) {
            ISecondLiveEditor.Attribute memory attribute_ = suitByIndex(
                suitId,
                i
            );
            uint256 nftID_ = editorNFT.mint(_mintTo, attribute_);
            emit EventClaim(nftID_, _dummyId, _mintTo);
        }
        isClaimed[_dummyId] = true;
        userClaimed[_mintTo] = true;
    }

    function updateTime(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
        emit UpdateTime(_startTime, _endTime);
    }

    function resetSuits() external onlyOwner {
        suitTypeSet.remove(suits.length);
        suits.pop();
    }

    function addSuits(uint256[][] memory _attributes) external onlyOwner {
        suitTypeSet.add(suits.length);
        suits.push(Suit({singles: _attributes}));
    }

    function suitLength() external view returns (uint256) {
        return suits.length;
    }

    function singleCountBySuitIndex(
        uint256 suitIndex
    ) external view returns (uint256) {
        Suit memory suit = suits[suitIndex];
        uint256[][] memory _attributes = suit.singles;
        return _attributes.length;
    }

    function suitByIndex(
        uint256 suitIndex,
        uint256 singleIndex
    ) public view returns (ISecondLiveEditor.Attribute memory _attribute) {
        Suit memory suit = suits[suitIndex];
        uint256[][] memory _attributes = suit.singles;
        uint256[] memory attribute = _attributes[singleIndex];

        _attribute.rule = attribute[0];
        _attribute.quality = attribute[1];
        _attribute.format = attribute[2];
        _attribute.extra = attribute[3];
    }
}

