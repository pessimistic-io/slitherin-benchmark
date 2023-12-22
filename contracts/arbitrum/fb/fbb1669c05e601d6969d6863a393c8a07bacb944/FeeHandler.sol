// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVoter.sol";
import "./IVotingEscrow.sol";
import "./IGauge.sol";
import "./IFeeDistributor.sol";
import "./INeadStake.sol";
import "./ISwappoor.sol";
import "./IBooster.sol";
import "./IVeDepositor.sol";

import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";

/**
    @notice contract that stores platform performance fees and handles bribe distribution
    @notice a callFee is set to incentivize bots to process performance fees / bribes instead of letting lp's shoulder the cost
    @notice any token sent to this contract will be processed!
    @dev performance fees and bribe claiming is separate 
*/

contract feeHandler is
    Initializable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN");

    address public treasury;
    address public ram;
    address public swapTo;
    address public veDepositor;
    address public proxyAdmin;
    address public aggregator;

    INeadStake public neadStake;
    ISwappoor public swap; // deprecated
    IBooster booster;
    IVoter voter;

    uint public bribeCallFee;
    uint public performanceCallFee;
    uint platformFee;
    uint treasuryFee;
    uint stakerFee;
    uint tokenID;
    mapping(address => bool) legacyIsApproved; // check if swapper is approved to spend a token
    // pool -> bribe
    mapping(address => address) public bribeForPool;

    mapping(address => bool) isApproved; // will have to reset some way if aggregator is switched
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    address public nfpDepositor;
    mapping(address => uint) unclaimedFees;
    address public xRam;
    uint lockPercent;
    event ClaimBribe(
        address indexed token,
        address indexed caller,
        uint amount,
        uint bounty
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _treasury,
        address setter,
        address _proxyAdmin,
        ISwappoor _swap,
        IBooster _booster,
        INeadStake _neadStake
    ) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
        _grantRole(SETTER_ROLE, setter);
        _grantRole(PROXY_ADMIN_ROLE, _proxyAdmin);
        _setRoleAdmin(PROXY_ADMIN_ROLE, PROXY_ADMIN_ROLE);
        proxyAdmin = _proxyAdmin;

        treasury = _treasury;
        swap = _swap;
        booster = _booster;
        voter = IVoter(_booster.voter());
        tokenID = booster.tokenID();
        ram = _booster.ram();
        veDepositor = _booster.veDepositor();
        neadStake = _neadStake;
        swapTo = swap.weth();
        IERC20Upgradeable(swapTo).approve(address(_neadStake), type(uint).max);

        IERC20Upgradeable(ram).approve(address(swap), type(uint).max);
        IERC20Upgradeable(ram).approve(veDepositor, type(uint).max);
        isApproved[ram] = true;
        IERC20Upgradeable(veDepositor).approve(address(swap), type(uint).max);
        IERC20Upgradeable(veDepositor).approve(
            address(neadStake),
            type(uint).max
        );
        isApproved[veDepositor] = true;
    }

    function notifyFees(address token, uint amount) external {
        require(msg.sender == nfpDepositor);
        unchecked {
            unclaimedFees[token] += amount;
        }
    }

    function setLockPercent(uint _lockPercent) external onlyRole(SETTER_ROLE) {
        lockPercent = _lockPercent;
    }

    function setXram(address _xRam) external onlyRole(SETTER_ROLE) {
        IERC20Upgradeable(_xRam).approve(address(neadStake), type(uint).max);
        xRam = _xRam;
    }

    function setNfpDepositor(
        address _nfpDepositor
    ) external onlyRole(SETTER_ROLE) {
        nfpDepositor = _nfpDepositor;
    }

    function setAggregator(address _aggregator) external onlyRole(SETTER_ROLE) {
        aggregator = _aggregator;
    }

    /// @notice syncs tokenId for booster, needed to make this contract function correctly
    function syncTokenId() external {
        tokenID = booster.tokenID();
    }

    function syncFees() external {
        platformFee = booster.platformFee();
        treasuryFee = booster.treasuryFee();
        stakerFee = booster.stakerFee();
    }

    function setSwapTo(address _swapTo) external onlyRole(SETTER_ROLE) {
        swapTo = _swapTo;
        IERC20Upgradeable(_swapTo).approve(address(neadStake), type(uint).max);
    }

    function setCallFees(
        uint _bribeCallFee,
        uint _performanceCallFee
    ) external onlyRole(SETTER_ROLE) {
        bribeCallFee = _bribeCallFee;
        performanceCallFee = _performanceCallFee;
    }

    function manualClaimBribes(
        address[] calldata rewarders,
        address[][] calldata tokens
    ) external onlyRole(HARVESTER_ROLE) {
        for (uint i; i < rewarders.length; ) {
            address[] memory _token = new address[](1);
            for (uint j; j < tokens[i].length; ) {
                _token[0] = tokens[i][j];
                try
                    IFeeDistributor(rewarders[i]).getReward(tokenID, _token)
                {} catch {
                    unchecked {
                        ++j;
                        continue;
                    }
                }
                uint bal = IERC20Upgradeable(tokens[i][j]).balanceOf(
                    address(this)
                );
                unchecked {
                    bal -= unclaimedFees[tokens[i][j]];
                }
                IERC20Upgradeable(tokens[i][j]).transfer(msg.sender, bal);
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice swaps/locks performance fees and sends to multiRewards
    function processPerformanceFees(
        address token
    ) public onlyRole(HARVESTER_ROLE) {
        booster.poke(token);
        IERC20Upgradeable _token = IERC20Upgradeable(token);
        uint bal = _token.balanceOf(address(this));
        uint treasuryShare;
        uint stakersShare;

        if (bal > 0) {
            unchecked {
                // calculate call fee
                uint fee = (bal * performanceCallFee) / 1e18;
                _token.transfer(msg.sender, fee);
                bal -= fee;
                // calculate fee to treasury
                treasuryShare = (bal * treasuryFee) / platformFee;
                // calculate fee to stakers
                stakersShare = (bal * stakerFee) / platformFee;
            }
            _token.transfer(treasury, treasuryShare);
            if (token == ram) {
                uint amountToLock = (stakersShare * lockPercent) / 1e18;
                IVeDepositor(veDepositor).depositTokens(amountToLock);
                neadStake.notifyRewardAmount(veDepositor, amountToLock);
                neadStake.notifyRewardAmount(ram, stakersShare - amountToLock);
            } else if (token == veDepositor) {
                neadStake.notifyRewardAmount(veDepositor, stakersShare);
            } else if (token == xRam) {
                neadStake.notifyRewardAmount(token, stakersShare);
            }
        }
        unclaimedFees[token] = 0;
    }

    function batchProcessPerformanceFees(address[] calldata tokens) external {
        for (uint i; i < tokens.length; ) {
            processPerformanceFees(tokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice swaps bribes to weth, or locks to neadRam if the reward token is ram and notifies multiRewards
    function processBribes(
        address feeDistributor,
        address[] calldata tokens,
        bytes calldata _data
    ) public onlyRole(HARVESTER_ROLE) {
        IFeeDistributor(feeDistributor).getReward(tokenID, tokens);
        uint fee;
        unchecked {
            for (uint i; i < tokens.length; ++i) {
                uint bal = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );

                if (bal > 0) {
                    fee = (bal * bribeCallFee) / 1e18;
                    if (tokens[i] == ram) {
                        IERC20Upgradeable(tokens[i]).transfer(msg.sender, fee);
                        IVeDepositor(veDepositor).depositTokens(bal - fee);
                        neadStake.notifyRewardAmount(veDepositor, bal - fee);
                        emit ClaimBribe(
                            veDepositor,
                            msg.sender,
                            bal - fee,
                            fee
                        );
                    } else if (tokens[i] == veDepositor) {
                        IERC20Upgradeable(tokens[i]).transfer(msg.sender, fee);
                        neadStake.notifyRewardAmount(tokens[i], bal - fee);
                        emit ClaimBribe(
                            veDepositor,
                            msg.sender,
                            bal - fee,
                            fee
                        );
                    } else if (tokens[i] == swapTo) {
                        IERC20Upgradeable(tokens[i]).transfer(msg.sender, fee);
                        neadStake.notifyRewardAmount(tokens[i], bal - fee);
                        emit ClaimBribe(swapTo, msg.sender, bal - fee, fee);
                    } else {
                        if (!isApproved[tokens[i]])
                            IERC20Upgradeable(tokens[i]).approve(
                                aggregator,
                                type(uint).max
                            );
                        uint amountOut = aggregatorSwap(_data);
                        fee = (amountOut * bribeCallFee) / 1e18;
                        IERC20Upgradeable(swapTo).transfer(msg.sender, fee);
                        neadStake.notifyRewardAmount(swapTo, amountOut - fee);
                        emit ClaimBribe(
                            swapTo,
                            msg.sender,
                            amountOut - fee,
                            fee
                        );
                    }
                }
            }
        }
    }

    /// @notice processes multiple bribes
    function batchProcessBribes(
        address[] calldata feeDistributors,
        address[][] calldata tokens,
        bytes[] calldata _data
    ) external {
        for (uint i; i < feeDistributors.length; ) {
            processBribes(feeDistributors[i], tokens[i], _data[i]);
            unchecked {
                ++i;
            }
        }
    }

    function aggregatorSwap(
        bytes calldata _data
    ) internal returns (uint amountOut) {
        (bool success, bytes memory returnData) = aggregator.call(_data);
        require(success, "Swap fail");
        amountOut = abi.decode(returnData, (uint));
    }

    function manualApprove(address token) external onlyRole(SETTER_ROLE) {
        IERC20Upgradeable(token).approve(address(neadStake), type(uint).max);
    }

    /// @notice sends tokens in the contract to `SETTER_ROLE`
    function recover(address[] calldata tokens) external onlyRole(SETTER_ROLE) {
        for (uint i; i < tokens.length; ++i) {
            uint bal = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
            IERC20Upgradeable(tokens[i]).transfer(msg.sender, bal);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(PROXY_ADMIN_ROLE) {}

    /// @dev grantRole already checks role, so no more additional checks are necessary
    function changeAdmin(address newAdmin) external {
        grantRole(PROXY_ADMIN_ROLE, newAdmin);
        renounceRole(PROXY_ADMIN_ROLE, proxyAdmin);
        proxyAdmin = newAdmin;
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

