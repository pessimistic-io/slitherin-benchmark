pragma solidity 0.8.10;

abstract contract IAspisConfiguration {
    uint256 internal constant maxFeePercentage = 1e4;

    uint256 public entranceFee;
    uint256 public performanceFee;
    uint256 public fundManagementFee;
    uint256 public rageQuitFee;
    
    uint256 public maxCap; //fundraising limit
    uint256 public minDeposit; 
    uint256 public maxDeposit;
    uint256 public startTime; //fundraising start time
    uint256 public finishTime;  //fundraising end time
    uint256 public withdrawlWindow;
    uint256 public freezePeriod;
    uint256 public lockLimit; //token lock up period
    uint256 public spendingLimit;
    uint256 public initialPrice;
    bool public canChangeManager;
    bool public canPerformDirectTransfer;

    function setConfiguration(address _aspisPool,
        address _registry,
        uint256[16] memory _poolconfig,
        address[] calldata _whitelistUsers,
        address[] calldata _trustedProtocols,
        address[] calldata _supportedTokens,
        address[] calldata _tradingTokens
    ) external virtual;

    function setRageQuitFee(uint256) external virtual;
    
    function getDepositLimit() public view virtual returns(uint256, uint256);

    function isPublicFund() public view virtual returns(bool);

    function getWhiteListUsers() public view virtual returns(address[] memory);

    function getTradingTokens() view public virtual returns(address[] memory);

    function getTrustedProtocols() view public virtual returns(address[] memory);

    function getDepositTokens() view public virtual returns(address[] memory);

    function supportsProtocol(address) view public virtual returns (bool);
    
    function supportsTradingToken(address) view public virtual returns (bool);
    
    function supportsDepositToken(address) view public virtual returns (bool);

    function userWhitelisted(address) view public virtual returns (bool);
    
    function getFees() public view returns(uint256, uint256, uint256, uint256) {
        return (entranceFee, performanceFee, fundManagementFee, rageQuitFee);
    }

    function calculateFundManagementFee(uint256 _tokenSupply, uint256 _managerShare) public view returns (uint256) {
        return (fundManagementFee * _tokenSupply) / (365 * (10000 - _managerShare) - fundManagementFee);
    }

}
