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

import "./IConsensusERC20.sol";

contract ConsensusERC20 is IConsensusERC20 {
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);

  string internal _name;
  string internal _symbol;

  uint8 public constant decimals = 18;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  bytes32 public DOMAIN_SEPARATOR;
  // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
  mapping(address => uint256) public nonces;

  constructor() {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(_name)),
        keccak256(bytes("1")),
        chainId,
        address(this)
      )
    );
  }

  function name() external view returns (string memory) {
    return _name;
  }

  function symbol() external view returns (string memory) {
    return _symbol;
  }

  function approve(address spender, uint256 value) external returns (bool) {
    _approve(msg.sender, spender, value);
    return true;
  }

  function transfer(address to, uint256 value) external returns (bool) {
    _transfer(msg.sender, to, value);
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) {
      allowance[from][msg.sender] -= value;
    }
    _transfer(from, to, value);
    return true;
  }

  function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external
  {
    require(deadline >= block.timestamp, "Consensus: EXPIRED");
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
      )
    );
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(recoveredAddress != address(0) && recoveredAddress == owner, "Consensus: INVALID_SIGNATURE");
    _approve(owner, spender, value);
  }

  function _mint(address to, uint256 value) internal {
    totalSupply += value;
    balanceOf[to] += value;
    emit Transfer(address(0), to, value);
  }

  function _burn(address from, uint256 value) internal {
    balanceOf[from] -= value;
    totalSupply -= value;
    emit Transfer(from, address(0), value);
  }

  function _approve(address owner, address spender, uint256 value) private {
    allowance[owner][spender] = value;
    emit Approval(owner, spender, value);
  }

  function _transfer(address from, address to, uint256 value) private {
    balanceOf[from] -= value;
    balanceOf[to] += value;
    emit Transfer(from, to, value);
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

