// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./SafeMath.sol";
import "./ChainlinkClient.sol";
import "./ConfirmedOwner.sol";
import "./interfaces_IERC20.sol";
import "./Strings.sol";

contract ERC20Redemption is ChainlinkClient, ConfirmedOwner {
  using SafeMath for uint256;
  using Chainlink for Chainlink.Request;

  bytes32 private jobId;
  uint256 private fee;

  uint256 public depositFee = 0; // Uses basis points. 1000 = 10%

  constructor() ConfirmedOwner(msg.sender) {
    setChainlinkToken(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
    setChainlinkOracle(0x21d8284c498A2Dad0213aFf6ae20e48305767183);
    jobId = "82824bcdfaf14e158885f3aa98ab1c11";

    fee = (1 * LINK_DIVISIBILITY) / 10;
  }

  event CreateRedemptionStarted(
    bytes32 redemptionId,
    bytes32 projectId,
    address creator,
    string name,
    uint256 tokenAmount,
    uint256 points,
    string actionName,
    string scoreType,
    address contractAddress,
    bool limitOnePerWallet
  );

  event CreateRedemptionCompleted(
    bytes32 redemptionId,
    bytes32 projectId,
    address creator,
    string name,
    uint256 tokenAmount,
    uint256 points,
    string actionName,
    string scoreType,
    address contractAddress,
    bool limitOnePerWallet,
    bool success
  );

  event RedemptionStarted(
    address redeemer,
    bytes32 redemptionId,
    bytes32 requestId
  );

  event RedemptionCompleted(
    address redeemer,
    bytes32 redemptionId,
    bytes32 requestId,
    bool success
  );

  event RedemptionDeposit(
    bytes32 redemptionId,
    uint256 depositAmountTotal,
    uint256 depositAmountAfterFee,
    uint256 poolBalance,
    address tokenContract
  );

  event RedemptionWithdrawal(
    bytes32 redemptionId,
    uint256 withdrawalAmount,
    uint256 poolBalance
  );

  event RedemptionStatusChange(bytes32 redemptionId, RedemptionStatus status);

  event RedemptionDeleted(bytes32 redemptionId);

  enum RedemptionStatus {
    Paused,
    Active
  }

  enum RedemptionAttemptStatus {
    Pending,
    Failure,
    Success
  }

  struct Redemption {
    bytes32 redemptionId;
    bytes32 projectId;
    address creator;
    string name;
    address contractAddress;
    RedemptionStatus status;
    uint256 tokenAmount;
    uint256 points;
    string actionName;
    string scoreType;
    uint256 poolBalance;
    bool limitOnePerWallet;
  }

  struct RedemptionAttempt {
    address redeemer;
    bytes32 redemptionId;
    bytes32 requestId;
    RedemptionAttemptStatus status;
  }

  mapping(bytes32 => Redemption) public redemptionIdToRedemption;
  mapping(bytes32 => Redemption) public redemptionIdToPendingRedemption;
  mapping(bytes32 => bytes32) public requestIdToRedemptionId;
  mapping(bytes32 => RedemptionAttempt) public requestIdToRedemptionAttempt;
  mapping(bytes32 => mapping(address => bool)) redemptionIdToWalletToHasRedeemed;

  string private createRedemptionEndpoint;
  string private redeemEndpoint;

  function setCreateRedemptionEndpoint(
    string memory _endpoint
  ) external onlyOwner {
    createRedemptionEndpoint = _endpoint;
  }

  function setRedeemEndpoint(string memory _endpoint) external onlyOwner {
    redeemEndpoint = _endpoint;
  }

  function setOracleAndJob(address _oracle) external onlyOwner {
    setChainlinkOracle(_oracle);
  }

  function createRedemption(
    bytes32 _redemptionId,
    bytes32 _projectId,
    string memory _name,
    uint256 _tokenAmount,
    uint256 _points,
    string memory _actionName,
    string memory _scoreType,
    address _contract,
    bool _limitOnePerWallet,
    string memory _verification
  ) public {
    require(_points > 0);

    require(
      redemptionIdToRedemption[_redemptionId].redemptionId != _redemptionId
    );

    Redemption storage _pendingRedemption = redemptionIdToPendingRedemption[
      _redemptionId
    ];

    _pendingRedemption.redemptionId = _redemptionId;
    _pendingRedemption.projectId = _projectId;
    _pendingRedemption.creator = msg.sender;
    _pendingRedemption.name = _name;
    _pendingRedemption.tokenAmount = _tokenAmount;
    _pendingRedemption.points = _points;
    _pendingRedemption.actionName = _actionName;
    _pendingRedemption.scoreType = _scoreType;
    _pendingRedemption.contractAddress = _contract;
    _pendingRedemption.limitOnePerWallet = _limitOnePerWallet;
    _pendingRedemption.status = RedemptionStatus.Active;

    bytes32 requestId = createCreateRedemptionRequest(
      _redemptionId,
      msg.sender,
      _verification
    );

    requestIdToRedemptionId[requestId] = _redemptionId;

    emit CreateRedemptionStarted(
      _redemptionId,
      _projectId,
      msg.sender,
      _name,
      _tokenAmount,
      _points,
      _actionName,
      _scoreType,
      _contract,
      _limitOnePerWallet
    );
  }

  function createCreateRedemptionRequest(
    bytes32 _redemptionId,
    address _creator,
    string memory _verification
  ) public returns (bytes32 requestId) {
    Chainlink.Request memory req = buildChainlinkRequest(
      jobId,
      address(this),
      this.fulfillCreateRedemption.selector
    );

    string memory requestUrl = string.concat(
      createRedemptionEndpoint,
      iToHex(
        abi.encodePacked(
          redemptionIdToPendingRedemption[_redemptionId].projectId
        )
      ),
      "&userAddress=",
      iToHex((abi.encodePacked(_creator))),
      "&scoreType=",
      redemptionIdToPendingRedemption[_redemptionId].scoreType,
      "&actionName=",
      redemptionIdToPendingRedemption[_redemptionId].actionName,
      "&actionPoints=",
      Strings.toString(redemptionIdToPendingRedemption[_redemptionId].points),
      "&verification=",
      _verification
    );

    req.add("get", requestUrl);

    req.add("path", "status");

    return sendChainlinkRequest(req, fee);
  }

  function fulfillCreateRedemption(
    bytes32 _requestId,
    string memory _status
  ) public recordChainlinkFulfillment(_requestId) {
    Redemption memory redemption = redemptionIdToPendingRedemption[
      requestIdToRedemptionId[_requestId]
    ];
    if (
      keccak256(abi.encodePacked(_status)) ==
      keccak256(abi.encodePacked("success"))
    ) {
      redemptionIdToRedemption[
        requestIdToRedemptionId[_requestId]
      ] = redemption;

      emit CreateRedemptionCompleted(
        redemption.redemptionId,
        redemption.projectId,
        redemption.creator,
        redemption.name,
        redemption.tokenAmount,
        redemption.points,
        redemption.actionName,
        redemption.scoreType,
        redemption.contractAddress,
        redemption.limitOnePerWallet,
        true
      );
    } else {
      emit CreateRedemptionCompleted(
        redemption.redemptionId,
        redemption.projectId,
        redemption.creator,
        redemption.name,
        redemption.tokenAmount,
        redemption.points,
        redemption.actionName,
        redemption.scoreType,
        redemption.contractAddress,
        redemption.limitOnePerWallet,
        false
      );
    }
  }

  function redeem(
    bytes32 _redemptionId,
    string memory _verification
  ) public returns (bytes32) {
    require(
      redemptionIdToRedemption[_redemptionId].status == RedemptionStatus.Active
    );
    require(
      redemptionIdToRedemption[_redemptionId].poolBalance >=
        redemptionIdToRedemption[_redemptionId].tokenAmount
    );

    if (redemptionIdToRedemption[_redemptionId].limitOnePerWallet == true) {
      require(
        redemptionIdToWalletToHasRedeemed[_redemptionId][msg.sender] == false
      );
    }

    bytes32 requestId = createRedeemRequest(
      _redemptionId,
      _verification,
      msg.sender
    );

    requestIdToRedemptionAttempt[requestId] = RedemptionAttempt(
      msg.sender,
      _redemptionId,
      requestId,
      RedemptionAttemptStatus.Pending
    );

    emit RedemptionStarted(msg.sender, _redemptionId, requestId);

    return requestId;
  }

  function createRedeemRequest(
    bytes32 _redemptionId,
    string memory _verification,
    address _redeemer
  ) public returns (bytes32 requestId) {
    Chainlink.Request memory req = buildChainlinkRequest(
      jobId,
      address(this),
      this.fulfillRedeem.selector
    );

    string memory requestUrl = string.concat(
      redeemEndpoint,
      iToHex(
        abi.encodePacked(redemptionIdToRedemption[_redemptionId].projectId)
      ),
      "&userAddress=",
      iToHex((abi.encodePacked(_redeemer))),
      "&scoreType=",
      redemptionIdToRedemption[_redemptionId].scoreType,
      "&action=",
      redemptionIdToRedemption[_redemptionId].actionName,
      "&points=",
      Strings.toString(redemptionIdToRedemption[_redemptionId].points),
      "&verification=",
      _verification
    );

    req.add("get", requestUrl);

    req.add("path", "status");

    return sendChainlinkRequest(req, fee);
  }

  function fulfillRedeem(
    bytes32 _requestId,
    string memory _status
  ) public recordChainlinkFulfillment(_requestId) {
    RedemptionAttempt memory redemptionAttempt = requestIdToRedemptionAttempt[
      _requestId
    ];

    if (
      keccak256(abi.encodePacked(_status)) ==
      keccak256(abi.encodePacked("success"))
    ) {
      redemptionIdToWalletToHasRedeemed[redemptionAttempt.redemptionId][
        redemptionAttempt.redeemer
      ] = true;

      IERC20(
        redemptionIdToRedemption[redemptionAttempt.redemptionId].contractAddress
      ).transfer(
          redemptionAttempt.redeemer,
          redemptionIdToRedemption[redemptionAttempt.redemptionId].tokenAmount
        );

      redemptionIdToRedemption[redemptionAttempt.redemptionId]
        .poolBalance = redemptionIdToRedemption[redemptionAttempt.redemptionId]
        .poolBalance
        .sub(
          redemptionIdToRedemption[redemptionAttempt.redemptionId].tokenAmount
        );

      requestIdToRedemptionAttempt[_requestId].status = RedemptionAttemptStatus
        .Success;

      emit RedemptionCompleted(
        redemptionAttempt.redeemer,
        redemptionAttempt.redemptionId,
        _requestId,
        true
      );
    } else {
      requestIdToRedemptionAttempt[_requestId].status = RedemptionAttemptStatus
        .Failure;

      emit RedemptionCompleted(
        redemptionAttempt.redeemer,
        redemptionAttempt.redemptionId,
        _requestId,
        false
      );
    }
  }

  function pauseRedemption(bytes32 _redemptionId) external {
    require(redemptionIdToRedemption[_redemptionId].creator == msg.sender);

    redemptionIdToRedemption[_redemptionId].status = RedemptionStatus.Paused;

    emit RedemptionStatusChange(_redemptionId, RedemptionStatus.Paused);
  }

  function resumeRedemption(bytes32 _redemptionId) external {
    require(redemptionIdToRedemption[_redemptionId].creator == msg.sender);

    redemptionIdToRedemption[_redemptionId].status = RedemptionStatus.Active;

    emit RedemptionStatusChange(_redemptionId, RedemptionStatus.Active);
  }

  function deleteRedemption(bytes32 _redemptionId) external {
    require(redemptionIdToRedemption[_redemptionId].creator == msg.sender);

    delete redemptionIdToRedemption[_redemptionId];

    emit RedemptionDeleted(_redemptionId);
  }

  function depositRedemptionPool(
    bytes32 _redemptionId,
    uint256 _tokenAmount
  ) external {
    require(redemptionIdToRedemption[_redemptionId].creator == msg.sender);
    require(
      IERC20(redemptionIdToRedemption[_redemptionId].contractAddress).allowance(
        msg.sender,
        address(this)
      ) >= _tokenAmount
    );

    uint256 tokenAmountAfterFee = _tokenAmount; // Token amount where fee will be removed

    if (depositFee > 0) {
      tokenAmountAfterFee =
        _tokenAmount -
        ((_tokenAmount * depositFee) / 10000);
    }

    IERC20(redemptionIdToRedemption[_redemptionId].contractAddress)
      .transferFrom(msg.sender, address(this), _tokenAmount);

    redemptionIdToRedemption[_redemptionId]
      .poolBalance = redemptionIdToRedemption[_redemptionId].poolBalance.add(
      tokenAmountAfterFee
    );

    emit RedemptionDeposit(
      _redemptionId,
      _tokenAmount,
      tokenAmountAfterFee,
      redemptionIdToRedemption[_redemptionId].poolBalance,
      redemptionIdToRedemption[_redemptionId].contractAddress
    );
  }

  function withdrawRedemptionPool(
    bytes32 _redemptionId,
    uint256 _tokenAmount
  ) external {
    require(redemptionIdToRedemption[_redemptionId].creator == msg.sender);
    require(
      redemptionIdToRedemption[_redemptionId].poolBalance >= _tokenAmount
    );

    IERC20(redemptionIdToRedemption[_redemptionId].contractAddress).transfer(
      msg.sender,
      _tokenAmount
    );

    redemptionIdToRedemption[_redemptionId]
      .poolBalance = redemptionIdToRedemption[_redemptionId].poolBalance.sub(
      _tokenAmount
    );

    emit RedemptionWithdrawal(
      _redemptionId,
      _tokenAmount,
      redemptionIdToRedemption[_redemptionId].poolBalance
    );
  }

  function setDepositFee(uint256 _depositFee) external onlyOwner {
    depositFee = _depositFee;
  }

  function getRedemption(
    bytes32 _redemptionId
  ) public view returns (Redemption memory) {
    return redemptionIdToRedemption[_redemptionId];
  }

  function getRedemptionAttempt(
    bytes32 _requestId
  ) public view returns (RedemptionAttempt memory) {
    return requestIdToRedemptionAttempt[_requestId];
  }

  function getRedemptionPoolBalance(
    bytes32 _redemptionId
  ) public view returns (uint256) {
    return redemptionIdToRedemption[_redemptionId].poolBalance;
  }

  function withdrawTokenFees(
    address _tokenContract,
    uint256 _tokenAmount
  ) public onlyOwner {
    require(IERC20(_tokenContract).transfer(msg.sender, _tokenAmount));
  }

  function withdrawLink() public onlyOwner {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(link.transfer(msg.sender, link.balanceOf(address(this))));
  }

  function iToHex(bytes memory buffer) public pure returns (string memory) {
    bytes memory converted = new bytes(buffer.length * 2);

    bytes memory _base = "0123456789abcdef";

    for (uint256 i = 0; i < buffer.length; i++) {
      converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
      converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
    }

    return string(abi.encodePacked("0x", converted));
  }
}

