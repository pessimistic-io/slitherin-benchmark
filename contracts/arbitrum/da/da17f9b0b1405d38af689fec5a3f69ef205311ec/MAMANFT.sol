// contracts/MAMANFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract MAMANFT is ERC721Enumerable, Ownable {
    string private _buri;

    bytes32 public wlMerkleRoot;

    uint256 public wlMmCost = 1 ether;
    uint256 public wlAaCost = 1 ether;
    uint256 public wlMamaCost = 1 ether;
    uint256 public plMmCost = 1 ether;
    uint256 public plAaCost = 1 ether;
    uint256 public plMamaCost = 1 ether;

    uint256 public wlMmActivityTimeStart;
    uint256 public wlMmActivityTimeEnd;
    uint256 public wlAaActivityTimeStart;
    uint256 public wlAaActivityTimeEnd;
    uint256 public wlMamaActivityTimeStart;
    uint256 public wlMamaActivityTimeEnd;
    uint256 public wlMamaActivityLimitTimeStart;
    uint256 public wlMamaActivityLimitTimeEnd;

    uint256 public plMmActivityTimeStart;
    uint256 public plMmActivityTimeEnd;
    uint256 public plAaActivityTimeStart;
    uint256 public plAaActivityTimeEnd;
    uint256 public plMamaActivityTimeStart;
    uint256 public plMamaActivityTimeEnd;


    uint8 public plMmMintAmountPreLimit = 10;
    uint8 public plAaMintAmountPreLimit = 10;
    uint8 public plMamaMintAmountPreLimit = 0;
    uint8 public wlMamaMintAmountPreLimit = 5;

    uint256 public plAndWlAaAmountLimit = 2000;
    uint256 public plAndWlAaMintCurrentAmount = 0;
    uint256 public wlMamaAmountLimit = 600;
    uint256 public wlMamaMintCurrentAmount = 0;


    mapping(address => uint256) public plMmMintRecord;
    mapping(address => uint256) public plAaMintRecord;
    mapping(address => uint256) public plMamaMintRecord;
    mapping(address => uint256) public wlMmMintRecord;
    mapping(address => uint256) public wlAaMintRecord;
    mapping(address => uint256) public wlMamaMintRecord;


    uint256 public mmAndAaAndMamaMintIndex = 601;
    uint256 public mamaMintIndex = 1;
    uint256 public ownerMintIndex = 100000000;

    constructor(string memory baseURI_)
    ERC721("MAMANFT", "MAMANFT")
    {
        setBaseURI(baseURI_);
    }

    function _baseURI() internal view override returns (string memory) {
        return _buri;
    }

    function setBaseURI(string memory buri_) public onlyOwner {
        require(bytes(buri_).length > 0, "wrong base uri");
        _buri = buri_;
    }

    function burn(uint256 _tokenId) public virtual {
        require(
            _isApprovedOrOwner(_msgSender(), _tokenId),
            "burn caller is not owner nor approved"
        );
        _burn(_tokenId);
    }

    function withdraw(uint256 _balance) public payable onlyOwner {
        (bool os,) = payable(owner()).call{value : _balance}("");
        require(os);
    }

    function setWlMerkleRoot(bytes32 _merkle) public onlyOwner {
        wlMerkleRoot = _merkle;
    }

    function setWlCost(uint256 _wlMmCost, uint256 _wlAaCost, uint256 _wlMamaCost) public onlyOwner {
        wlMmCost = _wlMmCost;
        wlAaCost = _wlAaCost;
        wlMamaCost = _wlMamaCost;
    }

    function setPlCost(uint256 _plMmCost, uint256 _plAaCost, uint256 _plMamaCost) public onlyOwner {
        plMmCost = _plMmCost;
        plAaCost = _plAaCost;
        plMamaCost = _plMamaCost;
    }

    function setWlActivityTime(uint256 _wlMmActivityTimeStart, uint256 _wlMmActivityTimeEnd, uint256 _wlAaActivityTimeStart, uint256 _wlAaActivityTimeEnd, uint256 _wlMamaActivityLimitTimeStart, uint256 _wlMamaActivityLimitTimeEnd, uint256 _wlMamaActivityTimeStart, uint256 _wlMamaActivityTimeEnd) public onlyOwner {
        wlMmActivityTimeStart = _wlMmActivityTimeStart;
        wlMmActivityTimeEnd = _wlMmActivityTimeEnd;
        wlAaActivityTimeStart = _wlAaActivityTimeStart;
        wlAaActivityTimeEnd = _wlAaActivityTimeEnd;
        wlMamaActivityLimitTimeStart = _wlMamaActivityLimitTimeStart;
        wlMamaActivityLimitTimeEnd = _wlMamaActivityLimitTimeEnd;
        wlMamaActivityTimeStart = _wlMamaActivityTimeStart;
        wlMamaActivityTimeEnd = _wlMamaActivityTimeEnd;
    }

    function setPlActivityTime(uint256 _plMmActivityTimeStart, uint256 _plMmActivityTimeEnd, uint256 _plAaActivityTimeStart, uint256 _plAaActivityTimeEnd, uint256 _plMamaActivityTimeStart, uint256 _plMamaActivityTimeEnd) public onlyOwner {
        plMmActivityTimeStart = _plMmActivityTimeStart;
        plMmActivityTimeEnd = _plMmActivityTimeEnd;
        plAaActivityTimeStart = _plAaActivityTimeStart;
        plAaActivityTimeEnd = _plAaActivityTimeEnd;
        plMamaActivityTimeStart = _plMamaActivityTimeStart;
        plMamaActivityTimeEnd = _plMamaActivityTimeEnd;
    }

    function setPlMmMintAmountPreLimit(uint8 _plMmMintAmountPreLimit) public onlyOwner {
        plMmMintAmountPreLimit = _plMmMintAmountPreLimit;
    }

    function setPlAaMintAmountPreLimit(uint8 _plAaMintAmountPreLimit) public onlyOwner {
        plAaMintAmountPreLimit = _plAaMintAmountPreLimit;
    }

    function setPlMamaMintAmountPreLimit(uint8 _plMamaMintAmountPreLimit) public onlyOwner {
        plMamaMintAmountPreLimit = _plMamaMintAmountPreLimit;
    }

    function setWlMamaMintAmountPreLimit(uint8 _wlMamaMintAmountPreLimit) public onlyOwner {
        wlMamaMintAmountPreLimit = _wlMamaMintAmountPreLimit;
    }

    function setWlMamaAmountLimit(uint256 _wlMamaAmountLimit) public onlyOwner {
        wlMamaAmountLimit = _wlMamaAmountLimit;
    }

    function setPlAndWlAaAmountLimit(uint256 _plAndWlAaAmountLimit) public onlyOwner {
        plAndWlAaAmountLimit = _plAndWlAaAmountLimit;
    }

    function setWlMamaMintCurrentAmount(uint256 _wlMamaMintCurrentAmount) public onlyOwner {
        wlMamaMintCurrentAmount = _wlMamaMintCurrentAmount;
    }

    function setPlAndWlAaMintCurrentAmount(uint256 _plAndWlAaMintCurrentAmount) public onlyOwner {
        plAndWlAaMintCurrentAmount = _plAndWlAaMintCurrentAmount;
    }

    function setMmAndAaAndMamaMintIndex(uint256 _mmAndAaAndMamaMintIndex) public onlyOwner {
        mmAndAaAndMamaMintIndex = _mmAndAaAndMamaMintIndex;
    }

    function setMamaMintIndex(uint256 _mamaMintIndex) public onlyOwner {
        mamaMintIndex = _mamaMintIndex;
    }

    function setOwnerMintIndex(uint256 _ownerMintIndex) public onlyOwner {
        ownerMintIndex = _ownerMintIndex;
    }

    function mintMmToPl(uint64 _amount) public payable {
        require(
            block.timestamp > plMmActivityTimeStart &&
            block.timestamp < plMmActivityTimeEnd,
            "activity offline"
        );
        require(_amount >= 1, "amount error");

        require(msg.value >= plMmCost * _amount, "insufficient funds");

        plMmMintRecord[msg.sender] = plMmMintRecord[msg.sender] + _amount;

        require(plMmMintRecord[msg.sender] <= plMmMintAmountPreLimit, "public amount limit");

        mintMmAaMama(msg.sender, _amount);
    }

    function mintAaToPl(uint64 _amount) public payable {
        require(
            block.timestamp > plAaActivityTimeStart &&
            block.timestamp < plAaActivityTimeEnd,
            "activity offline"
        );
        require(_amount >= 1, "amount error");

        require(msg.value >= plAaCost * _amount, "insufficient funds");

        plAndWlAaMintCurrentAmount = plAndWlAaMintCurrentAmount + _amount;
        require(plAndWlAaMintCurrentAmount <= plAndWlAaAmountLimit, "total amount limit");

        plAaMintRecord[msg.sender] = plAaMintRecord[msg.sender] + _amount;

        require(plAaMintRecord[msg.sender] <= plAaMintAmountPreLimit, "public amount limit");

        mintMmAaMama(msg.sender, _amount);
    }

    function mintMamaToPl(uint64 _amount) public payable {
        require(
            block.timestamp > plMamaActivityTimeStart &&
            block.timestamp < plMamaActivityTimeEnd,
            "activity offline"
        );
        require(_amount >= 1, "amount error");

        require(msg.value >= plMamaCost * _amount, "insufficient funds");

        plMamaMintRecord[msg.sender] = plMamaMintRecord[msg.sender] + _amount;

        require(plMamaMintRecord[msg.sender] <= plMamaMintAmountPreLimit, "public amount limit");

        mintMmAaMama(msg.sender, _amount);
    }

    function mintMmToWl(uint64 _amount, bytes32[] calldata _proof) public payable {
        require(
            block.timestamp > wlMmActivityTimeStart &&
            block.timestamp < wlMmActivityTimeEnd,
            "activity offline"
        );

        require(_amount >= 1, "amount error");

        require(msg.value >= wlMmCost * _amount, "insufficient funds");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_proof, wlMerkleRoot, leaf),
            "invalid proof"
        );

        wlMmMintRecord[msg.sender] = wlMmMintRecord[msg.sender] + _amount;

        mintMmAaMama(msg.sender, _amount);
    }

    function mintAaToWl(uint64 _amount, bytes32[] calldata _proof) public payable {
        require(
            block.timestamp > wlAaActivityTimeStart &&
            block.timestamp < wlAaActivityTimeEnd,
            "activity offline"
        );

        require(_amount >= 1, "amount error");

        require(msg.value >= wlAaCost * _amount, "insufficient funds");

        plAndWlAaMintCurrentAmount = plAndWlAaMintCurrentAmount + _amount;
        require(plAndWlAaMintCurrentAmount <= plAndWlAaAmountLimit, "total amount limit");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_proof, wlMerkleRoot, leaf),
            "invalid proof"
        );

        wlAaMintRecord[msg.sender] = wlAaMintRecord[msg.sender] + _amount;

        mintMmAaMama(msg.sender, _amount);
    }

    function mintMamaToWl(uint64 _amount, bytes32[] calldata _proof) public payable {
        require(
            block.timestamp > wlMamaActivityTimeStart &&
            block.timestamp < wlMamaActivityTimeEnd,
            "activity offline"
        );

        require(_amount >= 1, "amount error");

        require(msg.value >= wlMamaCost * _amount, "insufficient funds");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_proof, wlMerkleRoot, leaf),
            "invalid proof"
        );

        wlMamaMintCurrentAmount = wlMamaMintCurrentAmount + _amount;
        require(wlMamaMintCurrentAmount <= wlMamaAmountLimit, "total amount limit");

        wlMamaMintRecord[msg.sender] = wlMamaMintRecord[msg.sender] + _amount;
        require(wlMamaMintRecord[msg.sender] <= wlMamaMintAmountPreLimit, "whitelist amount limit");

        mintMmAaMama(msg.sender, _amount);
    }

    function mintMamaToWlLimit(uint64 _amount, bytes32[] calldata _proof) public payable {
        require(
            block.timestamp > wlMamaActivityLimitTimeStart &&
            block.timestamp < wlMamaActivityLimitTimeEnd,
            "activity offline"
        );

        require(_amount >= 1, "amount error");

        require(msg.value >= wlMamaCost * _amount, "insufficient funds");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_proof, wlMerkleRoot, leaf),
            "invalid proof"
        );

        wlMamaMintCurrentAmount = wlMamaMintCurrentAmount + _amount;
        require(wlMamaMintCurrentAmount <= wlMamaAmountLimit, "total amount limit");

        wlMamaMintRecord[msg.sender] = wlMamaMintRecord[msg.sender] + _amount;
        require(wlMamaMintRecord[msg.sender] <= wlMamaMintAmountPreLimit, "whitelist amount limit");

        for (uint256 i = 1; i <= _amount; i++) {
            _safeMint(msg.sender, mamaMintIndex++);
        }
    }

    function mintMmAaMama(address _to, uint64 _amount) private {
        for (uint256 i = 1; i <= _amount; i++) {
            _safeMint(_to, mmAndAaAndMamaMintIndex++);
        }
    }

    function mint(address _to, uint256 _tokenId) public onlyOwner {
        _safeMint(_to, _tokenId);
    }

    function mint(address[] memory _accounts, uint256 startIndex)
    public
    onlyOwner
    returns (uint256)
    {
        uint endIndex = _accounts.length + startIndex;
        for (uint256 i = startIndex; i < endIndex; i++) {
            mint(_accounts[i - startIndex], i);
        }
        return endIndex;
    }

    function mint(address _to) public onlyOwner returns (uint256){
        _safeMint(_to, ownerMintIndex++);
        return ownerMintIndex;
    }

    function mintBatch(address _to, uint256 _amount) public onlyOwner returns (uint256){
        for (uint256 i = 0; i < _amount; i++) {
            mint(_to);
        }
        return ownerMintIndex;
    }

}

