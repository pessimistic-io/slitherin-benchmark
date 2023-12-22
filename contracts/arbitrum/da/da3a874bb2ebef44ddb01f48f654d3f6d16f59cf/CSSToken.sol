/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";
import "./ERC20Capped.sol";
import "./AccessControl.sol";
import "./Math.sol";
import "./ITokenVesting.sol";

/**
 * @title Consensus Token
 * @author Consensus party
 * @notice This is an ERC20 token that has:
 *
 * - Token: Consensus Token (CSS)
 * - Permit: Consensus
 * - Max supply: the maximum token supply is set to 10 million CSS tokens.
 *
 * Please note that all of the token supply is a token vesting contract for further unlocking over time.
 */
contract ConsensusToken is ERC20Permit, ERC20Capped {
  uint256 internal constant MAX_TOTAL_SUPPLY = 10_000_000 ether;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  ITokenVesting public immutable tokenVesting;

  modifier onlyTokenVesting() {
    require(msg.sender == address(tokenVesting), "ConsensusToken: invalid sender");
    _;
  }

  constructor(ITokenVesting _tokenVesting, uint256 initSupply)
    ERC20("Consensus Token", "CSS")
    ERC20Permit("Consensus")
    ERC20Capped(MAX_TOTAL_SUPPLY)
  {
    require(_tokenVesting.IS_CONSENSUS_VESTING(), "ConsensusToken: invalid vesting");
    tokenVesting = _tokenVesting;

    _mint(msg.sender, initSupply);
  }

  fallback() external payable {}
  receive() external payable {}

  /**
   * @dev See {ERC20-_mint}.
   *
   * Requirements:
   *
   * - the caller must be token vesting.
   */
  function mint(address account, uint256 amount) external onlyTokenVesting {
    _mint(account, amount);
  }

  /**
   * @dev See {ERC20-_mint}. Returns the minted amount.
   *
   * Requirements:
   *
   * - the caller must be token vesting.
   */
  function safeMint(address account, uint256 amount) external onlyTokenVesting returns (uint256 minted) {
    minted = Math.min(amount, cap() - totalSupply());
    _mint(account, minted);
  }

  /**
   * @dev Rescues funds in case some tokens are unexpectedly transferred to this contract.
   * These tokens are transferred to token vesting contract `address(tokenVesting)`.
   *
   * @param tokens the token addresses.
   */
  function rescueTokens(IERC20[] calldata tokens) external onlyTokenVesting {
    address recipient = address(tokenVesting);
    uint256 ethBalance = address(this).balance;
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 balance = tokens[i].balanceOf(address(this));
      require(tokens[i].transfer(recipient, balance), "CSSToken: transfer failed");
    }

    if (ethBalance > 0) {
      (bool success,) = payable(recipient).call{value: ethBalance}(new bytes(0));
      require(success, "CSSToken: cannot withdraw");
    }
  }

  /**
   * @dev See {ERC20-_mint}.
   */
  function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20Capped) {
    super._mint(account, amount);
  }
}

/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

