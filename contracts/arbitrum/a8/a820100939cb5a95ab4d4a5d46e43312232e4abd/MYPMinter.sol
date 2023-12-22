//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";

import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";

import "./UserAccessible.sol";
import { IItems } from "./IItems.sol";

import { UserPunk } from "./MYP.sol";

/**
................................................
................................................
................................................
................................................
...................';::::::;'.';'...............
.............';'.':kNWWWWWWNkcod;...............
.............oXkckNWMMMMMMMMWNkc'.';'...........
.........'::ckWWWWMMMMMMMMMMMMWNkcoxo:'.........
.........;xKWWMMMMWXKNMMMMMMMMMMWNklkXo.........
.........'cOWMMMMN0kxk0XWWXK0KNWMMWWKk:.........
.......':okKWMMMWOldkdlkNNkcccd0NMMWOc'.........
.......;dolOWMWX0d:;::ckXXkc:;;:lkKWKko:'.......
.......':okKWN0dc,.',;:dOOkd:.''..lNOlod:.......
.....':kNklONx;;:,.';:::ccdkc.',. lWMNo.........
.....:xkOKWWWl..:::::::::::c:::;. lWMWk:'.......
.........dWMWl .:::::::;;;;:::::. lNXOkx;.......
. .....':okkk; .;::::::,'',:::::. ;xdc'.........
.......:d:...  .;::::;,,,,,,;:::.  .:d:.........
.. ..........  .';:::,'....',:;'.  .............
..............   .,,,;::::::;'.    .............
..............    .  .''''''.   ................
..............   ....          .................
..............   .;,....    . ..................
..............   .;:::;.    ....................

               Made with <3 from
             @author @goldendilemma

*/

interface IMYPNFT {
  function mintYourPunk (
    address to,
    address creator,
    UserPunk calldata punk
  ) external;
  function totalSupply() external returns (uint256);
}

struct PaymentInfo1155 {
  address addr;
  uint tokenId;
  bool specificToken;
  uint requiredBalance;
  bool enabled;
  bool shouldBurn;
}

struct PaymentInfo20 {
  address addr;
  uint requiredBalance;
  bool enabled;
}

enum TokenTypes {
  ETH,
  TERC20,
  TERC1155
}

contract MYPMinter is 
  UserAccessible,
  Pausable
{
  using SafeERC20 for IERC20;

  IMYPNFT myp;

  uint public mintSupply;
  uint public ethPrice;

  mapping (TokenTypes => mapping (uint => bool)) public guaranteedMint;

  address public paymentReceiver;
  mapping (uint => PaymentInfo1155) public paymentsERC1155;
  mapping (uint => PaymentInfo20) public paymentsERC20;

  constructor(address _userAccess)
    UserAccessible(_userAccess) 
  {}

  modifier mintsLeft (TokenTypes ttype, uint paymentId) {
    if (mintSupply > 0 && guaranteedMint[ttype][paymentId] == false) {
      require(myp.totalSupply() < mintSupply, "OUT_OF_MINTS");
    }
    _;
  }

  function pause () public onlyAdmin { _pause(); }
  function unpause () public onlyAdmin { _unpause(); }

  function setEthPrice (uint _ethPrice) public onlyAdmin { ethPrice = _ethPrice; }
  function setMintSupply (uint _mintSupply) public onlyAdmin { mintSupply = _mintSupply; }
  function setNFTContract (address nftContract) public onlyAdmin { myp = IMYPNFT(nftContract); }
  function setPaymentReceiver (address _paymentReceiver) public onlyAdmin { paymentReceiver = _paymentReceiver; }

  function setGuaranteedMint (TokenTypes ttype, uint paymentId, bool isGuaranteed) public onlyAdmin {
    guaranteedMint[ttype][paymentId] = isGuaranteed;
  }

  function setPIERC1155 (
    uint paymentId, 
    address addr, 
    bool specificToken,
    uint tokenId, 
    uint requiredBalance, 
    bool enabled,
    bool shouldBurn
  )
    public
    onlyAdmin
  {
    paymentsERC1155[paymentId] = PaymentInfo1155({
      addr: addr,
      tokenId: tokenId,
      specificToken: specificToken,
      requiredBalance: requiredBalance,
      enabled: enabled,
      shouldBurn: shouldBurn
    });
  }

  function setPIERC20 (
    uint paymentId, 
    address addr,
    uint requiredBalance, 
    bool enabled
  )
    public
    onlyAdmin
  {
    paymentsERC20[paymentId] = PaymentInfo20({
      addr: addr,
      requiredBalance: requiredBalance,
      enabled: enabled
    });
  }


  function withdraw (uint256 amount) 
    external 
    onlyAdmin
  {
    (bool success, ) = msg.sender.call { 
      value: amount
    }("");
    require(success, "NOT_ENOUGH_FUNDS");
  }


  function mintYourPunk (UserPunk calldata punk) 
    public 
    onlyAdmin 
  {
    myp.mintYourPunk(
      msg.sender, 
      msg.sender, 
      punk
    );
  }

  function mintWithETH (UserPunk calldata punk) 
    public 
    payable
    whenNotPaused
    mintsLeft(TokenTypes.ETH, 0)
  {
    require(ethPrice > 0, "ETH_NOT_READY");
    require(msg.value >= ethPrice, "NOT_ENOUGH_FUNDS");
    myp.mintYourPunk(
      msg.sender, 
      msg.sender, 
      punk
    );
  }

  function mintWithERC1155 (
    uint paymentId,
    uint tokenId,
    address to,
    UserPunk calldata punk
  ) 
    public 
    payable
    whenNotPaused
    mintsLeft(TokenTypes.TERC1155, paymentId)
  {
    _mintWithERC1155(paymentId, tokenId, msg.sender, to, punk);
  }

  function mintWithERC20 (
    uint paymentId,
    address to,
    UserPunk calldata punk
  ) 
    public 
    payable
    whenNotPaused
    mintsLeft(TokenTypes.TERC20, paymentId)
  {
    _mintWithERC20(paymentId, msg.sender, to, punk);
  }

  function _mintWithERC1155 (
    uint paymentId,
    uint tokenId,
    address from,
    address to,
    UserPunk calldata punk
  )
    private
  {
    PaymentInfo1155 memory pi = paymentsERC1155[paymentId];
    require(pi.enabled, "INVALID_PAYMENT");
    if (pi.specificToken) require(tokenId == pi.tokenId, 'INVALID_TOKEN');
    
    if (pi.shouldBurn) {
      IItems(pi.addr).burn(from, tokenId, pi.requiredBalance);
    } else {
      IERC1155(pi.addr).safeTransferFrom(from, paymentReceiver, tokenId, pi.requiredBalance, "");
    }
    myp.mintYourPunk(
      to, 
      to, 
      punk
    );
  }

  function _mintWithERC20 (
    uint paymentId,
    address from,
    address to,
    UserPunk calldata punk
  )
    private
  {
    PaymentInfo20 memory pi = paymentsERC20[paymentId];
    require(pi.enabled, "INVALID_PAYMENT");
    IERC20(pi.addr).safeTransferFrom(from, paymentReceiver, pi.requiredBalance);
    myp.mintYourPunk(
      to, 
      to, 
      punk
    );
  }
    
}

