//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./NFT.sol";
import "./DIAOracleV2.sol";

//TODO : withdraw event emit mainnet nft address

contract MintAsset is IERC1155Receiver {
  event Deposit(
    address indexed _nftAddressExternal,
    address indexed _from,
    uint256 indexed _nftID,
    bool _ethdropped,
    uint256 fee
  );

  event Withdraw(
    address indexed _nftAddress,
    address indexed _from,
    uint256 indexed _nftID
  );

  // map of mainnet - l2
  mapping(address => address) public nfts;

  // map of l2 - mainnet
  mapping(address => address) public nftExternal;

  using EnumerableSet for EnumerableSet.AddressSet;
  EnumerableSet.AddressSet private _allowedBridges;

  address public immutable owner;

  address public gasOracle; // Gas Fee oracle for l2 gas

  uint256 public withdrawGasLimit ;

  mapping(address => mapping(uint256 => bool)) public ethdropped;

  constructor(address oracle) {
    gasOracle = oracle;
    owner = msg.sender;
    _allowedBridges.add(msg.sender);
  }

  function _updateGasOracle(address _newOracle) external onlyOwner {
    gasOracle = _newOracle;
  }

  function _updateWithdrwaGasLimit(uint256 _newGasLimit) external onlyOwner {
    withdrawGasLimit = _newGasLimit;
  }

  function _calculateFee() public view returns (uint256) {
    (uint128 value, ) = DIAOracleV2(gasOracle).getValue(
      "GAS_ETH"
    );
    return value * withdrawGasLimit;
  }

  function getFee() public view returns (uint256) {
    return _calculateFee();
  }

  function isFeeRequired(address _nftAddress, uint256 _nftID)
    public
    view
    returns (bool)
  {
    return ethdropped[_nftAddress][_nftID];
  }

  function _addNFT(address _sourceNFT, address _destNFT) external onlyOwner {
    nfts[_sourceNFT] = _destNFT;
    nftExternal[_destNFT] = _sourceNFT;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "only owner can do this action");
    _;
  }

  function _exists(uint256 tokenId, address nft)
    internal
    view
    virtual
    returns (bool)
  {
    bool exist = false;
    if (ERC1155(nfts[nft]).balanceOf(address(this), tokenId) == 1) {
      exist = true;
    }
    return exist;
  }

  // Called by bridge service
  function _withdraw(
    address _to,
    uint256 _tokenId,
    address _nftAddress
  ) external {
    require(_allowedBridges.contains(msg.sender), "not a updater");
    require(_to != address(0), "cannot be the zero");
    require(_nftAddress != address(0), "cannot be the zero");
    if (_exists(_tokenId, _nftAddress)) {
      NFT(nfts[_nftAddress]).safeTransferFrom(
        address(this),
        _to,
        _tokenId,
        1,
        "0x0"
      );
    } else {
      NFT(nfts[_nftAddress]).mint(_to, _tokenId);
    }
    emit Withdraw(_nftAddress, _to, _tokenId);
  }

  function deposit(uint256 _nftID, address _nftAddress) external payable {
    require(
      IERC1155(_nftAddress).isApprovedForAll(msg.sender, address(this)),
      "approve missing"
    );
    if (isFeeRequired(_nftAddress, _nftID)) {
      require(msg.value >= _calculateFee(), "missing fee");
    }

    IERC1155(_nftAddress).safeTransferFrom(
      msg.sender,
      address(this),
      _nftID,
      1,
      "0x0"
    );
    emit Deposit(
      nftExternal[_nftAddress],
      msg.sender,
      _nftID,
      ethdropped[_nftAddress][_nftID],
      msg.value
    );
    ethdropped[_nftAddress][_nftID] = true;
  }

  function _setURI(string memory uri_, address nft) external onlyOwner {
    NFT(nfts[nft]).setURI(uri_);
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes memory
  ) public pure override returns (bytes4) {
    return
      bytes4(
        keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")
      );
  }

  function supportsInterface(bytes4 interfaceId)
    public
    pure
    override
    returns (bool)
  {
    return interfaceId == type(IERC1155Receiver).interfaceId;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) public pure override returns (bytes4) {
    return
      bytes4(
        keccak256(
          "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
        )
      );
  }

  function _addAllowedBridge(address _allowedBridge) external onlyOwner {
    _allowedBridges.add(_allowedBridge);
  }

  function _removeAllowedBridge(address _allowedBridge) external onlyOwner {
    _allowedBridges.remove(_allowedBridge);
  }

  function _removeAllowedBridges(address[] memory _allowedBridge)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _allowedBridge.length; i++) {
      _allowedBridges.remove(_allowedBridge[i]);
    }
  }

  function _withdrawETH() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  function withdrawToken(address _tokenContract, uint8 _amount)
    external
    onlyOwner
  {
    IERC20 tokenContract = IERC20(_tokenContract);
    tokenContract.transfer(msg.sender, _amount);
  }
}

