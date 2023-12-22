// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.7;

import "./ILongShortToken.sol";
import "./IHook.sol";

interface IPrePOMarket {
  event MarketCreated(
    address longToken,
    address shortToken,
    uint256 floorLongPayout,
    uint256 ceilingLongPayout,
    uint256 floorValuation,
    uint256 ceilingValuation,
    uint256 expiryTime
  );

  event Mint(address indexed minter, uint256 amount);

  event Redemption(
    address indexed redeemer,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );

  event MintHookChange(address hook);

  event RedeemHookChange(address hook);

  event FinalLongPayoutSet(uint256 payout);

  event RedemptionFeeChange(uint256 fee);

  function mint(uint256 amount) external returns (uint256);

  function redeem(
    uint256 longAmount,
    uint256 shortAmount,
    address recipient
  ) external;

  function setMintHook(IHook mintHook) external;

  function setRedeemHook(IHook redeemHook) external;

  function setFinalLongPayout(uint256 finalLongPayout) external;

  function setRedemptionFee(uint256 redemptionFee) external;

  function getMintHook() external view returns (IHook);

  function getRedeemHook() external view returns (IHook);

  function getCollateral() external view returns (IERC20);

  function getLongToken() external view returns (ILongShortToken);

  function getShortToken() external view returns (ILongShortToken);

  function getFloorLongPayout() external view returns (uint256);

  function getCeilingLongPayout() external view returns (uint256);

  function getFinalLongPayout() external view returns (uint256);

  function getFloorValuation() external view returns (uint256);

  function getCeilingValuation() external view returns (uint256);

  function getRedemptionFee() external view returns (uint256);

  function getExpiryTime() external view returns (uint256);

  function MAX_PAYOUT() external view returns (uint256);

  function FEE_DENOMINATOR() external view returns (uint256);

  function FEE_LIMIT() external view returns (uint256);

  function SET_MINT_HOOK_ROLE() external view returns (bytes32);

  function SET_REDEEM_HOOK_ROLE() external view returns (bytes32);

  function SET_FINAL_LONG_PAYOUT_ROLE() external view returns (bytes32);

  function SET_REDEMPTION_FEE_ROLE() external view returns (bytes32);
}

