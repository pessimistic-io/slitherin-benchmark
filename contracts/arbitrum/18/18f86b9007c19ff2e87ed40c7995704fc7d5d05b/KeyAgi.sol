// SPDX-License-Identifier: MIT
// A product of KeyofLife.fi
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./ISolidlyVoter.sol";
import "./IVeSolidly.sol";
import "./KolSolidlyManager.sol";
import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";
import "./SafeMath.sol";

interface ISolidlyStrategy {
    function want() external view returns (IERC20Upgradeable);
    function gauge() external view returns (address);
    function output() external view returns (address);
}

interface IVeDist {
    function claim(uint256 tokenId) external returns (uint256);
}

interface IGauge {
    function getReward(address user, address[] calldata tokens) external;

    function getReward(uint256 id, address[] calldata tokens) external;

    function deposit(uint256 amount, uint256 tokenId) external;

    function withdraw(uint256 amount) external;

    function balanceOf(address user) external view returns (uint256);

    function earned(address token, address account) external view returns (uint);
}

interface ImintBalancer {
    function shouldMint() external view returns (bool);
    function swap(address, bytes calldata, uint256) external;
    function keepPeg() external;
}

contract KeyAgi is KolSolidlyManager, ReentrancyGuardUpgradeable, ERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MAX_LOCK = (52 * 4 weeks);

    // Addresses used
    ISolidlyVoter public solidVoter;
    IVeSolidly public veToken;
    IVeDist public veDist;
    uint256 public veTokenId;
    IERC20Upgradeable public want;
    address public treasury;

    // Strategy mapping
    mapping(address => address) public whitelistedStrategy;
    mapping(address => address) private replacementStrategy;

    event SetTreasury(address treasury);
    event DepositWant(uint256 tvl);
    event Withdraw(uint256 amount);
    event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
    event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
    event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
    event ClaimRewards(address indexed user, address gauges, address[] tokens);
    event ClaimBribes(address indexed user, address[] _bribes, address[][] _tokens, uint256 veTokenId);
    event TransferVeToken(address indexed user, address to, uint256 veTokenId);
    event RecoverTokens(address token, uint256 amount);
    event Release(address indexed user, uint256 veTokenId, uint256 amount);

    address public mintBalancer;

    mapping (address => bool) public automatedMarketMakerPairs;
    address[] internal _markerPairs;
    uint256 constant totalBuyFees = 200;
    mapping(address => bool) public _isExcludedFromFee;
    address public constant uniRouter = 0x0FaE1e44655ab06825966a8fCE87b9e988AB6170;
    bool public autoPeg;
    uint256 public oneTimeSell;
    uint256 public maxTotalBuyFees;
    uint256 public minTotalBuyFees;
    ISolidlyPair public pair;

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AuthUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC20_init_unchained("KeyofLife.fi/keyAGI", "keyAGI");
        __SolidlyStaker_init(
            0x0fc90332260Dd4ffF8b2B69a37d8a754d39c4c90, // _solidVoter
            0x42684AEa9E4cE8F1BfaB865ab72f346D26E746f1, // _veDist
            0x4Dfa03c64ABd96359B77E7cCa8219B451C19f27E, // _treasury
            0x6AD874075469cB0D36e1C7313Db087C7ceC12738, //keeper
            0x6AD874075469cB0D36e1C7313Db087C7ceC12738, //voter
            0xFF191514A9baba76BfD19e3943a4d37E8ec9a111  // want = AGI
        );
        setExcludeFromFee(address(this),true);
        maxTotalBuyFees = 800;
    }

    function __SolidlyStaker_init(
        address _solidVoter,
        address _veDist,
        address _treasury,
        address _keeper,
        address _voter,
        address _want
    ) internal initializer {
        __KolSolidlyManager_init(_keeper, _voter);
        solidVoter = ISolidlyVoter(_solidVoter);
        veToken = IVeSolidly(solidVoter._ve());
        veDist = IVeDist(_veDist);
        treasury = _treasury;
        want = IERC20Upgradeable(_want);
        _giveAllowances();
    }

    // Checks that caller is the strategy assigned to a specific gauge.
    /*
    modifier onlyWhitelist(address _gauge) {
      require(whitelistedStrategy[_gauge] == msg.sender, "!whitelisted");
      _;
    }
  */
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        require(canMint(), "!canMint");
        uint256 _pool = balanceOfSolidlyToken();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfSolidlyToken();
        _amount = _after - (_pool);

        veToken.increase_amount(veTokenId, _amount);

        (, , bool shouldIncreaseLock) = lockInfo();
        if (shouldIncreaseLock) {
            veToken.increase_unlock_time(veTokenId, MAX_LOCK);
        }

        // Additional check for deflationary tokens

        if (_amount > 0) {
            //solidVoter.poke(veTokenId);
            _mint(msg.sender, _amount);
            emit DepositWant(totalSolidlyToken());
        }
        if (autoPeg && mintBalancer!=address(0) && mintBalancer!=msg.sender) {
            ImintBalancer(mintBalancer).keepPeg();
        }
    }
    /*
      function depositViaBalancer(address _oneInchRouter, bytes memory _data, uint256 _amount) external nonReentrant {
        require(!canMint(), "canMint");
        want.safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(want).safeApprove(mintBalancer, _amount);
        ImintBalancer(mintBalancer).swap(_oneInchRouter, _data, _amount);
      }

      // Pass through a deposit to a boosted gauge
      function depositForStrategyByOwner(address _gauge, uint256 _amount) external onlyOwner {
        address _strategy = whitelistedStrategy[_gauge];
        IERC20Upgradeable _underlying = ISolidlyStrategy(_strategy).want();
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount, veTokenId);
      }

      function depositForStrategy(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        IERC20Upgradeable _underlying = ISolidlyStrategy(msg.sender).want();
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount, veTokenId);
      }

      function withdrawAllForStrategy(address _gauge) external onlyWhitelist(_gauge) {
        withdrawForStrategy(_gauge,balanceOfStrategy(_gauge));
      }

      function withdrawForStrategy(address _gauge, uint256 _amount) public onlyWhitelist(_gauge) {
        IERC20Upgradeable _underlying = ISolidlyStrategy(msg.sender).want();
        uint256 _before = IERC20Upgradeable(_underlying).balanceOf(address(this));
        IGauge(_gauge).withdraw(_amount);
        uint256 _balance = _underlying.balanceOf(address(this)) - _before;
        _underlying.safeTransfer(msg.sender, _balance);
      }

      function balanceOfStrategy(address _gauge) public view returns (uint) {
        return IGauge(_gauge).balanceOf(address(this));
      }

      function getRewardsForStrategySimple() external {
        address _gauge = ISolidlyStrategy(msg.sender).gauge();
        require(whitelistedStrategy[_gauge]==msg.sender,"wrong strategy");
        address[] memory tokens = new address[](1);
        tokens[0] = ISolidlyStrategy(msg.sender).output();

        IGauge(_gauge).getReward(address(this), tokens);
        for (uint256 i; i < tokens.length; i++) {
          if (IERC20Upgradeable(tokens[i]).balanceOf(address(this))>0)
            IERC20Upgradeable(tokens[i]).safeTransfer(msg.sender, IERC20Upgradeable(tokens[i]).balanceOf(address(this)));
        }
      }

      function getRewardsForStrategy(address _gauge, address[] memory _tokens) external  onlyWhitelist(_gauge) {
        IGauge(_gauge).getReward(address(this), _tokens);
        for (uint256 i; i < _tokens.length; i++) {
          if (IERC20Upgradeable(_tokens[i]).balanceOf(address(this))>0)
            IERC20Upgradeable(_tokens[i]).safeTransfer(msg.sender, IERC20Upgradeable(_tokens[i]).balanceOf(address(this)));
        }
      }

      function earnedOfStrategy(address _gauge, address output) external view returns (uint) {
        return IGauge(_gauge).earned(output, address(this));
      }

      function whitelistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = ISolidlyStrategy(_strategy).want();
        address _gauge = ISolidlyStrategy(_strategy).gauge();
        uint256 stratBal = IGauge(_gauge).balanceOf(address(this));
        require(stratBal == 0, "!inactive");
        require(whitelistedStrategy[_gauge] == address(0),"already have this gauge");

        _want.safeApprove(_gauge, 0);
        _want.safeApprove(_gauge, type(uint256).max);
        whitelistedStrategy[_gauge] = _strategy;
      }

      function deleteStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = ISolidlyStrategy(_strategy).want();
        address _gauge = ISolidlyStrategy(_strategy).gauge();
        _want.safeApprove(_gauge, 0);
        whitelistedStrategy[_gauge] = address(0);
      }


    */
    function setAutomatedMarketMakerPair(address _dexPair, bool _status) public onlyOwner {
        require(automatedMarketMakerPairs[_dexPair] != _status,"already set");

        automatedMarketMakerPairs[_dexPair] = _status;

        if(_status){
            _markerPairs.push(_dexPair);
        }else{
            for (uint256 i = 0; i < _markerPairs.length; i++) {
                if (_markerPairs[i] == _dexPair) {
                    _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                    _markerPairs.pop();
                    break;
                }
            }
        }
    }

    function setExcludeFromFee(address account, bool value) public authorized {
        require(_isExcludedFromFee[account] != value, "Already set");
        _isExcludedFromFee[account] = value;
    }

    function calcBuyFee() public view returns(uint256) { //dynamic buy fee based on the imbalance in pool
        uint reserveDexToken;
        uint reserveKeyToken;
        if (pair.token1() == address(this))
            (reserveDexToken, reserveKeyToken, ) = pair.getReserves();
        else
            (reserveKeyToken, reserveDexToken, ) = pair.getReserves();

        uint ratio = 10000 * reserveKeyToken / (reserveKeyToken + reserveDexToken); // 5000 is ideal
        if (ratio<=5000) //healthy
            return minTotalBuyFees;
        else
            return minTotalBuyFees + ((ratio-5000) *  ( maxTotalBuyFees + minTotalBuyFees) / 10000);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {

        if (automatedMarketMakerPairs[from] && amount>0 && !_isExcludedFromFee[to]) {
            uint256 fees = amount * calcBuyFee() / 10000;
            super._transfer(from,address(this), fees); //1% buy tax
            amount -= fees;
        }
        super._transfer(from,to,amount);


    }



    function balanceOfSolidlyTokenInVe() public view returns (uint256) {
        return veToken.balanceOfNFT(veTokenId);
    }

    function balanceOfSolidlyToken() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    function lockInfo()
    public
    view
    returns (
        uint256 endTime,
        uint256 secondsRemaining,
        bool shouldIncreaseLock
    )
    {
        endTime = veToken.locked__end(veTokenId);
        uint256 unlockTime = ((block.timestamp + MAX_LOCK) / 1 weeks) * 1 weeks;
        secondsRemaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
        shouldIncreaseLock = unlockTime > endTime ? true : false;
    }

    function canMint() public view returns (bool) {
        if (mintBalancer == address(0)) return true;
        bool shouldMint = ImintBalancer(mintBalancer).shouldMint();
        return shouldMint;
    }

    function totalSolidlyToken() public view returns (uint256) {
        return balanceOfSolidlyToken() + (balanceOfSolidlyTokenInVe());
    }

    // --- Vote Related Functions ---

    // claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public {
        uint256 _amount = veDist.claim(veTokenId);
        emit ClaimVeEmissions(msg.sender, veTokenId, _amount);
    }

    // vote for emission weights
    function vote(address[] calldata _vaultVotes, uint256[] calldata _weights) external onlyVoter {
        claimVeEmissions();
        solidVoter.vote(veTokenId, _vaultVotes, _weights);
    }

    // reset current votes
    function resetVote() external onlyVoter {
        solidVoter.reset(veTokenId);
    }

    function claimMultipleOwnerRewards(address[] calldata _gauges, address[][] calldata _tokens) external onlyManager {
        for (uint256 i; i < _gauges.length; ) {
            claimOwnerRewards(_gauges[i], _tokens[i]);
        unchecked {
            ++i;
        }
        }
    }

    // claim owner rewards such as trading fees and bribes from gauges, transferred to treasury
    function claimOwnerRewards(address _gauge, address[] memory _tokens) public onlyManager {
        IGauge(_gauge).getReward(veTokenId, _tokens);
        for (uint256 i; i < _tokens.length; ) {
            address _reward = _tokens[i];
            uint256 _rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));

            if (_rewardBal > 0) {
                IERC20Upgradeable(_reward).safeTransfer(treasury, _rewardBal);
            }
        unchecked {
            ++i;
        }
        }

        emit ClaimRewards(msg.sender, _gauge, _tokens);
    }

    // --- Token Management ---

    // create a new veToken if none is assigned to this address
    function createLock(
        uint256 _amount,
        uint256 _lock_duration,
        bool init
    ) external onlyManager {
        require(veTokenId == 0, "veToken > 0");

        if (init) {
            veTokenId = veToken.tokenOfOwnerByIndex(msg.sender, 0);
            veToken.safeTransferFrom(msg.sender, address(this), veTokenId);
        } else {
            require(_amount > 0, "amount == 0");
            want.safeTransferFrom(address(msg.sender), address(this), _amount);
            veTokenId = veToken.create_lock(_amount, _lock_duration);
            _mint(msg.sender, _amount);

            emit CreateLock(msg.sender, veTokenId, _amount, _lock_duration);
        }
    }

    /**
     * @dev Merges two veTokens into one. The second token is burned and its balance is added to the first token.
   * @param _fromId The ID of the token to merge into the first token.
   */
    function merge(uint256 _fromId) external {
        require(_fromId != veTokenId, "cannot burn main veTokenId");
        veToken.safeTransferFrom(msg.sender, address(this), _fromId);
        veToken.merge(_fromId, veTokenId);
    }

    // extend lock time for veToken to increase voting power
    function increaseUnlockTime(uint256 _lock_duration) external onlyManager {
        veToken.increase_unlock_time(veTokenId, _lock_duration);
        emit IncreaseTime(msg.sender, veTokenId, _lock_duration);
    }

    function increaseAmount(uint256 amount) internal {
        uint256 bal = Math.min(amount,IERC20Upgradeable(address(want)).balanceOf(address(this)));
        //require(bal > 0, "no balance");
        if (bal>0) {
            veToken.increase_amount(veTokenId, bal);
            _mint((address(this)), bal);
        }

    }
    /*
      function lockHarvestAmount(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        want.safeTransferFrom(msg.sender, address(this), _amount);
        veToken.increase_amount(veTokenId, _amount);
      }
    */
    // transfer veToken to another address, must be detached from all gauges first
    function transferVeToken(address _to) external onlyOwner {
        uint256 transferId = veTokenId;
        //veTokenId = 0;
        veToken.safeTransferFrom(address(this), _to, transferId);

        emit TransferVeToken(msg.sender, _to, transferId);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // confirmation required for receiving veToken to smart contract
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external view returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        require(msg.sender == address(veToken), "!veToken");
        return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
    }

    /**
     * @notice  Gives approval for all necessary tokens to all necessary contracts
   */
    function _giveAllowances() internal {
        IERC20Upgradeable(want).safeApprove(address(veToken), type(uint256).max);
    }

    /**
     * @notice  Removes approval for all necessary tokens to all necessary contracts
   */
    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeApprove(address(veToken), 0);
    }

    function setmintBalancer(address _mintBalancer) external onlyOwner {
        mintBalancer = _mintBalancer;
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        if (_token==address(0)) {
            (bool success, ) = msg.sender.call{value: address(this).balance}(new bytes(0));
            require(success, "TransferHelper: ETH_TRANSFER_FAILED");
            return;
        }
        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
    }

    /*
      function setExternalVoter(address _voter) external onlyManager {
            emit NewVoter(_voter);
            voter = _voter;
            veToken.setApprovalForAll(_voter,true);
            veToken.approve(_voter,veTokenId);
      }
    */
    function poke() external onlyManager {
        solidVoter.poke(veTokenId);
    }

    function setAutoPeg(bool _autoPeg, uint256 _oneTimeSell) external onlyOwner {
        autoPeg = _autoPeg;
        oneTimeSell = _oneTimeSell;
    }

    function setBuyFees(uint256 _minTotalBuyFees, uint256 _maxTotalBuyFees) external onlyOwner {
        require(_minTotalBuyFees<=2000 && _maxTotalBuyFees<=2000,">20%");
        minTotalBuyFees = _minTotalBuyFees;
        maxTotalBuyFees = _maxTotalBuyFees;
    }

    // claim owner rewards such as trading fees and bribes from gauges, transferred to treasury
    function claimOwnerBribes(address[] memory _bribes, address[][] memory _tokens) public onlyManager {
        solidVoter.claimBribes(_bribes, _tokens, veTokenId);
        for (uint256 i; i < _bribes.length; i++ ) {
            for (uint256 j; j < _tokens[i].length; j++ ) {
                address _reward = _tokens[i][j];
                uint256 _rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));
                if (_rewardBal > 0) {
                    IERC20Upgradeable(_reward).safeTransfer(treasury, _rewardBal);
                }
            }
        }
        emit ClaimBribes(msg.sender, _bribes, _tokens, veTokenId);
    }

    function updatePair() external onlyOwner {
        pair = ISolidlyPair(ISolidlyRouter(uniRouter).pairFor(address(this), address(want), true));
        setAutomatedMarketMakerPair(address(pair),true);
    }


    function updateV2() external onlyOwner {
        minTotalBuyFees = 150;
    }

}
