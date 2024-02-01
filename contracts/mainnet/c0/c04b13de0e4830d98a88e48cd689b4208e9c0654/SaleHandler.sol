// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./ERC20.sol";
import "./IDiversificationUpgrade.sol";
import "./IAmountCalculator.sol";
import "./IPredicateHelper.sol";
import "./EIP712Alien.sol";
import "./Types.sol";

contract SaleHandler is ERC20, EIP712Alien {
  address internal constant GOVERNANCE = 0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce;
  address internal constant TORN = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint256 internal constant SALT = 1;

  bytes32 private constant LIMIT_ORDER_TYPEHASH =
    keccak256(
      "Order(uint256 salt,address makerAsset,address takerAsset,address maker,address receiver,address allowedSender,uint256 makingAmount,uint256 takingAmount,bytes makerAssetData,bytes takerAssetData,bytes getMakerAmount,bytes getTakerAmount,bytes predicate,bytes permit,bytes interaction)"
    );

  address public immutable oneInch; // 1Inch limit order protocol contract
  uint256 public immutable saleAmount; // TORN amount to be sold
  uint256 public immutable saleDuration;
  uint256 public immutable vestingDuration;
  uint256 public wethAmount; // WETH amount to be received
  uint256 public endSaleDate;
  uint256 public endVestingDate;
  bool public finalized;

  modifier onlyGovernance() {
    require(msg.sender == GOVERNANCE, "SH: only governance");
    _;
  }

  constructor(
    string memory name,
    string memory ticker,
    address _oneInch,
    uint256 _saleAmount,
    uint256 _saleDuration,
    uint256 _vestingDuration
  ) ERC20(name, ticker) EIP712Alien(_oneInch, "1inch Limit Order Protocol", "2") {
    oneInch = _oneInch;
    saleAmount = _saleAmount;
    saleDuration = _saleDuration;
    vestingDuration = _vestingDuration;
  }

  function initializeSale(uint256 _wethAmount) external onlyGovernance {
    require(ERC20(TORN).balanceOf(address(this)) >= saleAmount, "SH: torn balance not enough");
    wethAmount = _wethAmount;
    endSaleDate = block.timestamp + saleDuration;
    endVestingDate = endSaleDate + vestingDuration;

    // approve TORN to governance for locks
    ERC20(TORN).approve(GOVERNANCE, type(uint256).max);

    // mint and approve vesting token
    _mint(address(this), saleAmount);
    _approve(address(this), oneInch, saleAmount);
  }

  // @notice 1Inch limit order protocol signature check method
  function isValidSignature(bytes32 hash, bytes memory) public view returns (bytes4) {
    Types.Order memory order = Types.Order({
      salt: SALT,
      makerAsset: address(this),
      takerAsset: WETH,
      maker: address(this),
      receiver: GOVERNANCE,
      allowedSender: address(0),
      makingAmount: saleAmount,
      takingAmount: wethAmount,
      makerAssetData: bytes(""),
      takerAssetData: bytes(""),
      getMakerAmount: abi.encodeWithSelector(IAmountCalculator.getMakerAmount.selector, saleAmount, wethAmount),
      getTakerAmount: abi.encodeWithSelector(IAmountCalculator.getTakerAmount.selector, saleAmount, wethAmount),
      predicate: abi.encodeWithSelector(IPredicateHelper.timestampBelow.selector, endSaleDate),
      permit: bytes(""),
      interaction: bytes("")
    });

    require(hash == _hash(order), "SH: invalid signature");

    return this.isValidSignature.selector;
  }

  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal virtual override {
    if (recipient == GOVERNANCE) {
      require(sender == msg.sender, "SH: TransferFrom to GOVERNANCE is restricted");
      _burn(sender, amount);
      // check end vesting date
      if (block.timestamp >= endVestingDate) {
        // send real TORN to buyer
        require(ERC20(TORN).transfer(sender, amount), "SH: failed to send TORN");
      } else {
        // lock real TORN on governance
        IDiversificationUpgrade(GOVERNANCE).lockWithVestingTo(sender, amount, endVestingDate);
      }
      return;
    }

    if (sender == address(this)) {
      require(!isSaleFinished(), "SH: sale has been finished");
    }
    super._transfer(sender, recipient, amount);
  }

  function finalizeSale() external {
    require(isSaleFinished(), "SH: sale is not finished");
    require(!finalized, "SH: sale has been already finalized");
    finalized = true;

    // send unsold TORN tokens back to the governance
    uint256 unsoldTokens = balanceOf(address(this));
    if (unsoldTokens > 0) {
      require(ERC20(TORN).transfer(GOVERNANCE, unsoldTokens), "SH: failed to send TORN");
      // burn unsold VTORN
      _burn(address(this), unsoldTokens);
    }
  }

  function isSaleFinished() public view returns (bool) {
    return block.timestamp >= endSaleDate;
  }

  function _hash(Types.Order memory order) internal view returns (bytes32) {
    Types.StaticOrder memory staticOrder;
    assembly {
      // solhint-disable-line no-inline-assembly
      staticOrder := order
    }
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            LIMIT_ORDER_TYPEHASH,
            staticOrder,
            keccak256(order.makerAssetData),
            keccak256(order.takerAssetData),
            keccak256(order.getMakerAmount),
            keccak256(order.getTakerAmount),
            keccak256(order.predicate),
            keccak256(order.permit),
            keccak256(order.interaction)
          )
        )
      );
  }
}

