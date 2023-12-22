/// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "./IHypervisor.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./FullMath.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./ReentrancyGuard.sol";

interface IClearing {

	function clearDeposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address pos,
    uint256[4] memory minIn
  ) external view returns (bool cleared);

  function clearDepositWhitelisted(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address pos,
    uint256[4] memory minIn
  ) external view returns (bool cleared);

	function clearShares(
    address pos,
    uint256 shares
  ) external view returns (bool cleared);

  function getDepositAmount(
    address pos,
    address token,
    uint256 _deposit
  ) external view returns (uint256 amountStart, uint256 amountEnd);
}

/// @title UniProxy v1.2.3
/// @notice Proxy contract for hypervisor positions management
contract UniProxy is ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
	IClearing public clearance;
  address public owner;

  constructor(address _clearance) {
    owner = msg.sender;
		clearance = IClearing(_clearance);	
  }
  event PositionAdded(address, uint8);
  event ListAppended(address pos, address[] listed);
  event ListRemoved(address pos, address listed);
  uint256 constant MAX_UINT = 2**256 - 1;
  mapping(address => Position) public positions;

  struct Position {
    mapping(address=>bool) list; // whitelist certain accounts for freedeposit
    uint8 version; 
  }

    // @notice check if an address is whitelisted for hype
  function getListed(address pos, address i) public view returns(bool) {
    Position storage p = positions[pos];
    return p.list[i];
  }

  modifier onlyAddedPosition(address pos) {
    Position storage p = positions[pos];
    require(p.version != 0, "not added");
    _;
  } 


  /// @notice Add the hypervisor position
  /// @param pos Address of the hypervisor
  /// @param version Type of hypervisor
  function addPosition(address pos, uint8 version) external onlyOwner {
    Position storage p = positions[pos];
    require(p.version == 0, 'already added');
    require(version > 0, 'version < 1');
    p.version = version;
    IHypervisor(pos).token0().safeApprove(pos, MAX_UINT);
    IHypervisor(pos).token1().safeApprove(pos, MAX_UINT);
    emit PositionAdded(pos, version);
  }

  /// @notice Deposit into the given position
  /// @param deposit0 Amount of token0 to deposit
  /// @param deposit1 Amount of token1 to deposit
  /// @param to Address to receive liquidity tokens
  /// @param pos Hypervisor Address
  /// @param minIn min assets to expect in position during a direct deposit 
  /// @return shares Amount of liquidity tokens received
  function deposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address pos,
    uint256[4] memory minIn
  ) nonReentrant external returns (uint256 shares) {
    Position storage p = positions[pos];
    require(to != address(0), "to should be non-zero");
		if(positions[pos].list[msg.sender]){
            require(clearance.clearDepositWhitelisted(deposit0, deposit1, to, pos, minIn), "deposit not cleared");
    }
    if(!positions[pos].list[msg.sender]){
      require(clearance.clearDeposit(deposit0, deposit1, to, pos, minIn), "deposit not cleared");
    }
		/// transfer assets from msg.sender and mint lp tokens to provided address 
		shares = IHypervisor(pos).deposit(deposit0, deposit1, to, msg.sender, minIn);
		require(clearance.clearShares(pos, shares), "shares not cleared");
  }

  /// @notice Get the amount of token to deposit for the given amount of pair token
  /// @param pos Hypervisor Address
  /// @param token Address of token to deposit
  /// @param _deposit Amount of token to deposit
  /// @return amountStart Minimum amounts of the pair token to deposit
  /// @return amountEnd Maximum amounts of the pair token to deposit
  function getDepositAmount(
    address pos,
    address token,
    uint256 _deposit
  ) public view returns (uint256 amountStart, uint256 amountEnd) {
		return clearance.getDepositAmount(pos, token, _deposit);
	}

	function transferClearance(address newClearance) external onlyOwner {
    require(newClearance != address(0), "newClearance should be non-zero");
		clearance = IClearing(newClearance);
	}
  /// @notice Append whitelist to hypervisor
  /// @param pos Hypervisor Address
  /// @param listed Address array to add in whitelist
  function appendList(address pos, address[] memory listed) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    for (uint8 i; i < listed.length; i++) {
      p.list[listed[i]] = true;
    }
    emit ListAppended(pos, listed);
  }

  /// @notice Remove address from whitelist
  /// @param pos Hypervisor Address
  /// @param listed Address to remove from whitelist
  function removeListed(address pos, address listed) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.list[listed] = false;
    emit ListRemoved(pos, listed);
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "newOwner should be non-zero");
    owner = newOwner;
  }

  modifier onlyOwner {
    require(msg.sender == owner, "only owner");
    _;
  }
}

