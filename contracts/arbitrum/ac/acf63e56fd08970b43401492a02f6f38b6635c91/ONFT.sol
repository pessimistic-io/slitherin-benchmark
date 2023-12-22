// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ONFT721.sol";

contract ONFT is ONFT721, Pausable, ReentrancyGuard {
    using Strings for uint;
    using SafeERC20 for IERC20;

    uint public startMintId;
    uint public immutable endMintId;
    uint public price;
    uint public maxMintQuantity;
    bool public reveal;
    bool public isMintActive;
    string public contractURI;
    string public customName;
    string public customSymbol;
    IERC20 public immutable stableToken;
    mapping(address => uint) public claimed;
    address public feeCollectorAddress;

    /// @notice Constructor for the ONFT
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    /// @param _baseTokenURI the base URI for computing the tokenURI
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _startMintId the starting mint number on this chain
    /// @param _endMintId the max number of mints on this chain
    /// @param _stableTokenAddress the address of the stable contract to pay for mints
    /// @param _stableTokenDecimals the decimals of the stable token
    /// @param _feeCollectorAddress the address fee collector
    constructor(string memory _name, string memory _symbol, string memory _baseTokenURI, address _layerZeroEndpoint, uint _startMintId, uint _endMintId, address _stableTokenAddress, uint _stableTokenDecimals, address _feeCollectorAddress) ONFT721(_name, _symbol, _layerZeroEndpoint) {
        customName = _name;
        customSymbol = _symbol;
        setBaseURI(_baseTokenURI);
        contractURI = _baseTokenURI;
        startMintId = _startMintId;
        endMintId = _endMintId;
        stableToken = IERC20(_stableTokenAddress);
        maxMintQuantity = 3;
        price = 400 * 10**_stableTokenDecimals;
        feeCollectorAddress = _feeCollectorAddress;
    }

    function mint(uint _quantity) external {
        require(isMintActive, "ONFT: Mint is not active.");
        require(claimed[msg.sender] + _quantity <= maxMintQuantity, "ONFT: Max Mint per wallet reached.");
        require(startMintId + _quantity <= endMintId, "ONFT: Max Mint limit reached.");
        stableToken.safeTransferFrom(msg.sender, feeCollectorAddress, price * _quantity);
        claimed[msg.sender] = claimed[msg.sender] + _quantity;
        for (uint i = 1; i <= _quantity; i++) {
            _safeMint(msg.sender, startMintId++);
        }
    }

    function _beforeSend(address, uint16, bytes memory, uint _tokenId) internal override whenNotPaused {
        _burn(_tokenId);
    }

    function pauseSendTokens(bool pause) external onlyOwner {
        pause ? _pause() : _unpause();
    }

    function activateReveal() external onlyOwner {
        reveal = true;
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        if (reveal) {
            return string(abi.encodePacked(_baseURI(), tokenId.toString()));
        }
        return _baseURI();
    }

    function activateMint() external onlyOwner {
        isMintActive = true;
    }

    function setFeeCollector(address _feeCollectorAddress) external onlyOwner {
        feeCollectorAddress = _feeCollectorAddress;
    }

    function setMintPrice(uint _price) external onlyOwner {
        price = _price;
    }

    function setMintQuantity(uint _maxMintQuantity) external onlyOwner {
        maxMintQuantity = _maxMintQuantity;
    }

    function setContractURI(string memory _contractURI) public onlyOwner {
        contractURI = _contractURI;
    }

    function setName(string memory name) external onlyOwner {
        customName = name;
    }

    function setSymbol(string memory symbol) external onlyOwner {
        customSymbol = symbol;
    }

    function name() public view virtual override returns (string memory) {
        return customName;
    }

    function symbol() public view virtual override returns (string memory) {
        return customSymbol;
    }
}

