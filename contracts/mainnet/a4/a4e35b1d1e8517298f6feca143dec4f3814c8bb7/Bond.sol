// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC721.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ITreasury.sol";

contract ApeBond is ERC721, Ownable {
  event CreateBond(uint256 id, address asset, uint256 termLength);
  event RemoveBond(uint256 id);

  using Counters for Counters.Counter;
  Counters.Counter private _bondIds;
  ITreasury public immutable treasury;
  IERC20 public immutable apeToken;
  string private _baseURI_;

  constructor(address _treasury) ERC721('ApeDAO Token Bond', 'ATB') {
    treasury = ITreasury(_treasury);
    apeToken = IERC20(_treasury);
  }

  struct BondInfo {
    address asset;
    uint128 pricingTarget;
    uint128 termLength;
  }

  struct Bond {
    address backedToken;
    uint256 startTime;
    uint256 endTime;
    uint256 apeTotal;
    uint256 apeClaimed;
  }

  mapping(uint256 => BondInfo) public bonds;
  mapping(uint256 => Bond) public bond;

  function createBond(address asset, uint256 id, uint128 pricingTarget, uint128 termLength) public onlyOwner {
    require(treasury.isSupportedAsset(asset) == true, "ApeBond: Token not active");
    require(asset != address(0) && termLength > 0, "ApeBond: Invalid input");
    require(bonds[id].asset == address(0), "ApeBond: Bond ID exists");
    bonds[id] = BondInfo(asset, pricingTarget, termLength);
    emit CreateBond(id, asset, termLength);
  }
  
  function removeBond(uint256 id) public onlyOwner {
    require(bonds[id].asset != address(0), "ApeBond: Bond ID invalid");
    bonds[id].asset = address(0);
    emit RemoveBond(id);
  }
  
  function setBaseURI(string memory uriSlice) public onlyOwner {
    _baseURI_ = uriSlice;
  }

  function _baseURI() internal view override returns (string memory) {
    return _baseURI_;
  }

  function setBondPricingTarget(uint256 index, uint128 target) public onlyOwner {
    require(target > 0, "ApeBond: Cannot be 0%");
    bonds[index].pricingTarget = target;
  }

  function bondPrice(uint128 id) public view returns (uint256 price) {
    (price,) = _bondPrice(id);
  }

  function _bondPrice(uint128 id) internal view returns (uint256 price, uint256 fee) {
    BondInfo storage _bond = bonds[id];
    (uint256 _price, uint256 reserves, uint256 totalReserves, uint256 assetRatioPoints) = treasury.assetReserveDetails(_bond.asset);
    uint256 treasuryShare = (reserves * 100000) / totalReserves;
    uint256 targetMultiplier = (treasuryShare * 100000) / assetRatioPoints;
    uint256 premium = (_bond.pricingTarget * targetMultiplier) / 100000;
    price = ((premium + 100000) * _price) / 100000;
    fee = (price - _price) / 10;
  }

  function mintBond(uint128 id, uint256 amount) public {
    BondInfo storage _bond = bonds[id];
    require(_bond.asset != address(0), "ApeBond: Bond ID invalid");
    require(treasury.isSupportedAsset(_bond.asset) == true, "ApeBond: Token not active");
    
    (uint256 _price, uint256 _fee) = _bondPrice(id);
    _fee = (amount * _fee) / 1e18; 
    uint256 apeAmount = (amount * 1e18 ) / _price;
    address vaultAddr = treasury.mint(apeAmount, _bond.asset);
    IERC20(_bond.asset).transferFrom(msg.sender, vaultAddr, amount - _fee);
    IERC20(_bond.asset).transferFrom(msg.sender, owner(), _fee);

    _bondIds.increment();
    uint256 bondId = _bondIds.current();
    bond[bondId] = Bond({ backedToken: _bond.asset, startTime: block.timestamp, endTime: block.timestamp + _bond.termLength, apeTotal: apeAmount, apeClaimed: 0 });
    _safeMint(msg.sender, bondId);
    emit CreateBond(bondId, _bond.asset, _bond.termLength);
  }

  function redeem(uint256[] memory ids) public {
    uint256 claimAmount;
    for (uint i = 0; i < ids.length; i++) {
      require(ownerOf(ids[i]) == msg.sender, "ApeBond: Bond not owned");
      uint256 claim = pendingClaim(ids[i]);
      Bond storage _bond = bond[ids[i]];
      if (claim > 0) {
        _bond.apeClaimed = _bond.apeClaimed + claim;
        claimAmount = claimAmount + claim;
      }
      if (_bond.apeClaimed == _bond.apeTotal) {
        _burn(ids[i]);
      }
    }
    apeToken.transfer(msg.sender, claimAmount); 
  }

  function pendingClaim(uint256 id) public view returns (uint256 amount) {
    Bond storage _bond = bond[id];
    uint256 time = _bond.endTime - _bond.startTime;
    uint256 _now = block.timestamp > _bond.endTime ? _bond.endTime : block.timestamp;
    uint256 passed = _now - _bond.startTime;
    return ((passed * _bond.apeTotal) / time) - _bond.apeClaimed;
  }

}

