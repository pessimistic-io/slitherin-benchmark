pragma solidity >=0.7.0 <0.9.0;

interface IVeVARA {
  event Approval(
    address indexed owner,
    address indexed approved,
    uint256 indexed tokenId
  );
  event ApprovalForAll(
    address indexed owner,
    address indexed operator,
    bool approved
  );
  event DelegateChanged(
    address indexed delegator,
    address indexed fromDelegate,
    address indexed toDelegate
  );
  event DelegateVotesChanged(
    address indexed delegate,
    uint256 previousBalance,
    uint256 newBalance
  );
  event Deposit(
    address indexed provider,
    uint256 tokenId,
    uint256 value,
    uint256 indexed locktime,
    uint8 deposit_type,
    uint256 ts
  );
  event Supply(uint256 prevSupply, uint256 supply);
  event Transfer(
    address indexed from,
    address indexed to,
    uint256 indexed tokenId
  );
  event Withdraw(
    address indexed provider,
    uint256 tokenId,
    uint256 value,
    uint256 ts
  );

  function DELEGATION_TYPEHASH() external view returns (bytes32);

  function DOMAIN_TYPEHASH() external view returns (bytes32);

  function MAX_DELEGATES() external view returns (uint256);

  function abstain(uint256 _tokenId) external;

  function approve(address _approved, uint256 _tokenId) external;

  function artProxy() external view returns (address);

  function attach(uint256 _tokenId) external;

  function attachments(uint256) external view returns (uint256);

  function balanceOf(address _owner) external view returns (uint256);

  function balanceOfAtNFT(uint256 _tokenId, uint256 _block)
  external
  view
  returns (uint256);

  function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

  function balanceOfNFTAt(uint256 _tokenId, uint256 _t)
  external
  view
  returns (uint256);

  function block_number() external view returns (uint256);

  function checkpoint() external;

  function checkpoints(address, uint32)
  external
  view
  returns (uint256 timestamp);

  function create_lock(uint256 _value, uint256 _lock_duration)
  external
  returns (uint256);

  function create_lock_for(
    uint256 _value,
    uint256 _lock_duration,
    address _to
  ) external returns (uint256);

  function decimals() external view returns (uint8);

  function delegate(address delegatee) external;

  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function delegates(address delegator) external view returns (address);

  function deposit_for(uint256 _tokenId, uint256 _value) external;

  function detach(uint256 _tokenId) external;

  function epoch() external view returns (uint256);

  function getApproved(uint256 _tokenId) external view returns (address);

  function getPastTotalSupply(uint256 timestamp)
  external
  view
  returns (uint256);

  function getPastVotes(address account, uint256 timestamp)
  external
  view
  returns (uint256);

  function getPastVotesIndex(address account, uint256 timestamp)
  external
  view
  returns (uint32);

  function getVotes(address account) external view returns (uint256);

  function get_last_user_slope(uint256 _tokenId)
  external
  view
  returns (int128);

  function increase_amount(uint256 _tokenId, uint256 _value) external;

  function increase_unlock_time(uint256 _tokenId, uint256 _lock_duration)
  external;

  function isApprovedForAll(address _owner, address _operator)
  external
  view
  returns (bool);

  function isApprovedOrOwner(address _spender, uint256 _tokenId)
  external
  view
  returns (bool);

  function locked(uint256) external view returns (int128 amount, uint256 end);

  function locked__end(uint256 _tokenId) external view returns (uint256);

  function merge(uint256 _from, uint256 _to) external;

  function name() external view returns (string memory);

  function nonces(address) external view returns (uint256);

  function numCheckpoints(address) external view returns (uint32);

  function ownerOf(uint256 _tokenId) external view returns (address);

  function ownership_change(uint256) external view returns (uint256);

  function point_history(uint256)
  external
  view
  returns (
    int128 bias,
    int128 slope,
    uint256 ts,
    uint256 blk
  );

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external;

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes memory _data
  ) external;

  function setApprovalForAll(address _operator, bool _approved) external;

  function setArtProxy(address _proxy) external;

  function setTeam(address _team) external;

  function setVoter(address _voter) external;

  function slope_changes(uint256) external view returns (int128);

  function supply() external view returns (uint256);

  function supportsInterface(bytes4 _interfaceID)
  external
  view
  returns (bool);

  function symbol() external view returns (string memory);

  function team() external view returns (address);

  function token() external view returns (address);

  function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex)
  external
  view
  returns (uint256);

  function tokenURI(uint256 _tokenId) external view returns (string memory);

  function totalSupply() external view returns (uint256);

  function totalSupplyAt(uint256 _block) external view returns (uint256);

  function totalSupplyAtT(uint256 t) external view returns (uint256);

  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external;

  function user_point_epoch(uint256) external view returns (uint256);

  function user_point_history(uint256, uint256)
  external
  view
  returns (
    int128 bias,
    int128 slope,
    uint256 ts,
    uint256 blk
  );

  function user_point_history__ts(uint256 _tokenId, uint256 _idx)
  external
  view
  returns (uint256);

  function version() external view returns (string memory);

  function voted(uint256) external view returns (bool);

  function voter() external view returns (address);

  function voting(uint256 _tokenId) external;

  function withdraw(uint256 _tokenId) external;
}
