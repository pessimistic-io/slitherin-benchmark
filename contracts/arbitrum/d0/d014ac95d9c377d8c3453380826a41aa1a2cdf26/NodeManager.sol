// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./IERC20.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20Burnable.sol";
import "./IUniswapV2Router02.sol";

struct Tier {
    uint8 id;
    string name;
    uint256 price;
    uint256 rewardsPerTime;
    uint32 claimInterval;
}

struct Node {
    uint32 id;
    uint8 tierIndex;
    address owner;
    uint32 createdTime;
    uint32 claimedTime;
    uint32 limitedTime;
    uint256 multiplier;
}

contract NodeManager is Initializable, OwnableUpgradeable {
    address public tokenAddress;
    address public rewardsPoolAddress;
    address public operationsPoolAddress;

    bool public swapOnCreate;

    uint8 public tierTotal;
    uint8 public maxMonthValue;
    uint32 public countTotal;
    uint32 public rewardsPoolFee;
    uint32 public operationsPoolFee;
    uint32 public maintenanceFee;
    uint32 public payInterval; // 1 Month
    uint256 public rewardsTotal;

    mapping(string => uint8) public tierMap;
    mapping(address => uint256[]) public nodesOfUser;
    mapping(address => uint32) public countOfUser;
    mapping(string => uint32) public countOfTier;
    mapping(address => bool) public _isBlacklisted;
    mapping(address => uint256) public rewardsOfUser;

    Tier[] private tierArr;
    Node[] public nodesTotal;
    IUniswapV2Router02 public uniswapV2Router;

    event NodeCreated(address, string, uint32, uint32, uint32, uint32);

    function initialize(
        address _token,
        address _rewardsPoolAddress,
        address _operationsPoolAddress
    ) public initializer {
        __Ownable_init();
        tokenAddress = _token;
        rewardsPoolAddress = _rewardsPoolAddress;
        operationsPoolAddress = _operationsPoolAddress;

        addTier(
            "basic", // name
            100 ether, // price
            6.66667 ether, // rewards per time
            1 days // claim interval
        ); // maintenance fee

        rewardsPoolFee = 9500; // 95%
        operationsPoolFee = 500; // 5%

        payInterval = 15 days;
        maxMonthValue = 3;
        swapOnCreate = true;
    }

    function setSwapOnCreate(bool value) public onlyOwner {
        swapOnCreate = value;
    }

    function setPayInterval(uint32 value) public onlyOwner {
        payInterval = value;
    }

    function setRewardsPoolFee(uint32 value) public onlyOwner {
        rewardsPoolFee = value;
    }

    function setRewardsPoolAddress(address account) public onlyOwner {
        rewardsPoolAddress = account;
    }

    function setMaxMonthValue(uint8 value) public onlyOwner {
        maxMonthValue = value;
    }

    function setOperationsPoolFee(uint32 value) public onlyOwner {
        operationsPoolFee = value;
    }

    function setOperationsPoolAddress(address account) public onlyOwner {
        operationsPoolAddress = account;
    }

    function setRouter(address router) public onlyOwner {
        uniswapV2Router = IUniswapV2Router02(router);
    }

    function setAddressInBlacklist(address walletAddress, bool value)
        public
        onlyOwner
    {
        _isBlacklisted[walletAddress] = value;
    }

    function setTokenAddress(address token) public onlyOwner {
        tokenAddress = token;
    }

    function setmaintenanceFee(uint32 value) public onlyOwner {
        maintenanceFee = value;
    }

    function tiers() public view returns (Tier[] memory) {
        Tier[] memory tiersActive = new Tier[](tierTotal);
        uint8 j = 0;
        for (uint8 i = 0; i < tierArr.length; i++) {
            Tier storage tier = tierArr[i];
            if (tierMap[tier.name] > 0) tiersActive[j++] = tier;
        }
        return tiersActive;
    }

    function addTier(
        string memory _name,
        uint256 _price,
        uint256 _rewardsPerTime,
        uint32 _claimInterval
    ) public onlyOwner {
        require(_price > 0, "price");
        require(_rewardsPerTime > 0, "rewards");
        require(_claimInterval > 0, "claim");
        tierArr.push(
            Tier({
                id: uint8(tierArr.length),
                name: _name,
                price: _price,
                rewardsPerTime: _rewardsPerTime,
                claimInterval: _claimInterval
            })
        );
        tierMap[_name] = uint8(tierArr.length);
        tierTotal++;
    }

    function updateTier(
        string memory tierName,
        string memory name,
        uint256 price,
        uint256 rewardsPerTime,
        uint32 claimInterval
    ) public onlyOwner {
        uint8 tierId = tierMap[tierName];
        require(tierId > 0, "Old");
        require(
            keccak256(bytes(tierName)) != keccak256(bytes(name)),
            "name incorrect"
        );
        require(price > 0, "price");
        require(rewardsPerTime > 0, "rewardsPerTime");
        Tier storage tier = tierArr[tierId - 1];
        tier.name = name;
        tier.price = price;
        tier.rewardsPerTime = rewardsPerTime;
        tier.claimInterval = claimInterval;
        tierMap[tierName] = 0;
        tierMap[name] = tierId;
    }

    function removeTier(string memory tierName) public virtual onlyOwner {
        require(tierMap[tierName] > 0, "removed");
        tierMap[tierName] = 0;
        tierTotal--;
    }

    function nodes(address account) public view returns (Node[] memory) {
        Node[] memory nodesActive = new Node[](countOfUser[account]);
        uint256[] storage nodeIndice = nodesOfUser[account];
        uint32 j = 0;
        for (uint32 i = 0; i < nodeIndice.length; i++) {
            uint256 nodeIndex = nodeIndice[i];
            if (nodeIndex > 0) {
                Node storage node = nodesTotal[nodeIndex - 1];
                if (node.owner == account) {
                    nodesActive[j] = node;
                    nodesActive[j++].multiplier = 1 ether;
                }
            }
        }
        return nodesActive;
    }

    function _create(
        address account,
        string memory tierName,
        uint32 count
    ) private returns (uint256) {
        require(!_isBlacklisted[msg.sender], "Blacklisted");

        uint8 tierId = tierMap[tierName] - 1;
        uint256 tierPrice = tierArr[tierId].price;
        uint32 createdTime = uint32(block.timestamp);
        for (uint32 i = 0; i < count; i++) {
            nodesTotal.push(
                Node({
                    id: uint32(nodesTotal.length),
                    tierIndex: tierId,
                    owner: account,
                    multiplier: 0,
                    createdTime: createdTime,
                    claimedTime: createdTime,
                    limitedTime: createdTime + payInterval
                })
            );
            nodesOfUser[account].push(nodesTotal.length);
        }
        countOfUser[account] += count;
        countOfTier[tierName] += count;
        countTotal += count;
        uint256 amount = tierPrice * count;
        return amount;
    }

    function _transferFee(uint256 amount) private {
        uint256 rewardPoolAmount = (amount * rewardsPoolFee) / 10000;
        uint256 operationsPoolAmount = (amount * operationsPoolFee) / 10000;

        IERC20(tokenAddress).transferFrom(
            address(msg.sender),
            address(rewardsPoolAddress),
            rewardPoolAmount
        );

        IERC20(tokenAddress).transferFrom(
            address(msg.sender),
            address(this),
            operationsPoolAmount
        );

        if (swapOnCreate) {
            swapTokensForEth(
                tokenAddress,
                operationsPoolAddress,
                operationsPoolAmount
            );
        } else {
            IERC20(tokenAddress).transfer(
                address(operationsPoolAddress),
                operationsPoolAmount
            );
        }
    }

    function mint(
        address[] memory accounts,
        string memory tierName,
        uint32 count
    ) public onlyOwner {
        require(accounts.length > 0, "Empty");
        for (uint256 i = 0; i < accounts.length; i++) {
            _create(accounts[i], tierName, count);
        }
    }

    function create(string memory tierName, uint32 count) public {
        uint256 amount = _create(msg.sender, tierName, count);
        _transferFee(amount);
        emit NodeCreated(
            msg.sender,
            tierName,
            count,
            countTotal,
            countOfUser[msg.sender],
            countOfTier[tierName]
        );
    }

    function claimable(address _account) external view returns (uint256) {
        (uint256 claimableAmount, , ) = _iterate(_account, 0, 0);
        return claimableAmount + rewardsOfUser[_account];
    }

    function _claim(address _account) private {
        (
            uint256 claimableAmount,
            uint32 count,
            uint256[] memory nodeIndice
        ) = _iterate(_account, 0, 0);

        if (claimableAmount > 0) {
            rewardsOfUser[_account] += claimableAmount;
            rewardsTotal = rewardsTotal + claimableAmount;
        }

        for (uint32 i = 0; i < count; i++) {
            uint256 index = nodeIndice[i];
            Node storage node = nodesTotal[index - 1];
            node.claimedTime = uint32(block.timestamp);
        }
    }

    function compound(string memory tierName, uint32 count) public {
        uint256 amount = _create(msg.sender, tierName, count);
        _claim(msg.sender);
        require(rewardsOfUser[msg.sender] >= amount, "Insuff");

        rewardsOfUser[msg.sender] -= amount;
        emit NodeCreated(
            msg.sender,
            tierName,
            count,
            countTotal,
            countOfUser[msg.sender],
            countOfTier[tierName]
        );
    }

    function claim() public {
        _claim(msg.sender);

        IERC20(tokenAddress).transferFrom(
            address(rewardsPoolAddress),
            address(msg.sender),
            rewardsOfUser[msg.sender]
        );
        rewardsOfUser[msg.sender] = 0;
    }

    function burnUser(address account) public onlyOwner {
        uint256[] storage nodeIndice = nodesOfUser[account];
        for (uint32 i = 0; i < nodeIndice.length; i++) {
            uint256 nodeIndex = nodeIndice[i];
            if (nodeIndex > 0) {
                Node storage node = nodesTotal[nodeIndex - 1];
                if (node.owner == account) {
                    node.owner = address(0);
                    node.claimedTime = uint32(0);
                    Tier storage tier = tierArr[node.tierIndex];
                    countOfTier[tier.name]--;
                }
            }
        }
        nodesOfUser[account] = new uint256[](0);
        countTotal -= countOfUser[account];
        countOfUser[account] = 0;
    }

    function burnNodes(uint32[] memory indice) public onlyOwner {
        uint32 count = 0;

        for (uint32 i = 0; i < indice.length; i++) {
            uint256 nodeIndex = indice[i];

            if (nodeIndex >= 0) {
                Node storage node = nodesTotal[nodeIndex];
                if (node.owner != address(0)) {
                    uint256[] storage nodeIndice = nodesOfUser[node.owner];

                    for (uint32 j = 0; j < nodeIndice.length; j++) {
                        if (nodeIndex == nodeIndice[j]) {
                            nodeIndice[j] = 0;
                            break;
                        }
                    }
                    countOfUser[node.owner]--;
                    node.owner = address(0);
                    node.claimedTime = uint32(0);
                    Tier storage tier = tierArr[node.tierIndex];
                    countOfTier[tier.name]--;
                    count++;
                }
                // return a percentage of price to the owner
            }
        }
        countTotal -= count;
    }

    function withdraw(address anyToken, address recipient) external onlyOwner {
        IERC20(anyToken).transfer(
            recipient,
            IERC20(anyToken).balanceOf(address(this))
        );
    }

    function pay(uint8 count) public payable {
        require(
            count > 0 && count <= maxMonthValue,
            "Invalid number of months"
        );
        uint256 fee = 0;

        uint256[] storage nodeIndice = nodesOfUser[msg.sender];
        for (uint32 i = 0; i < nodeIndice.length; i++) {
            uint256 nodeIndex = nodeIndice[i];
            if (nodeIndex > 0) {
                Node storage node = nodesTotal[nodeIndex - 1];
                if (node.owner == msg.sender) {
                    node.limitedTime += count * uint32(payInterval);

                    Tier storage tier = tierArr[node.tierIndex];
                    fee += getAmountOut(
                        ((tier.price * maintenanceFee) / 10000) * count
                    );

                    //fee += 1000000;
                }
            }
        }

        require(fee <= msg.value, "Fee");
        payable(address(operationsPoolAddress)).transfer(fee);
    }

    function getUnpaidNodes() public view returns (uint32[] memory) {
        uint32 count = 0;
        for (uint32 i = 0; i < nodesTotal.length; i++) {
            Node storage node = nodesTotal[i];
            if (
                node.owner != address(0) &&
                node.limitedTime <= uint32(block.timestamp)
            ) {
                count++;
            }
        }
        uint32[] memory nodesInactive = new uint32[](count);
        uint32 j = 0;
        for (uint32 i = 0; i < nodesTotal.length; i++) {
            Node storage node = nodesTotal[i];
            if (
                node.owner != address(0) &&
                node.limitedTime <= uint32(block.timestamp)
            ) {
                nodesInactive[j] = node.id;
                j++;
            }
        }
        return nodesInactive;
    }

    function getAmountOut(uint256 _amount) public view returns (uint256) {
        if (address(uniswapV2Router) == address(0)) return 0;
        address[] memory path = new address[](2);
        path[0] = address(tokenAddress);
        path[1] = uniswapV2Router.WETH();
        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(
            _amount,
            path
        );
        return amountsOut[1];
    }

    function _iterate(
        address _account,
        uint8 _tierId,
        uint32 _count
    )
        private
        view
        returns (
            uint256,
            uint32,
            uint256[] memory
        )
    {
        uint32 count = 0;
        uint256 claimableAmount = 0;
        uint256 nodeIndiceLength = nodesOfUser[_account].length;
        uint256[] memory nodeIndiceResult = new uint256[](nodeIndiceLength);

        for (uint32 i = 0; i < nodeIndiceLength; i++) {
            uint256 nodeIndex = nodesOfUser[_account][i];

            if (nodeIndex > 0) {
                address nodeOwner = nodesTotal[nodeIndex - 1].owner;
                uint8 nodeTierIndex = nodesTotal[nodeIndex - 1].tierIndex;
                uint32 nodeClaimedTime = nodesTotal[nodeIndex - 1].claimedTime;

                if (_tierId != 0 && nodeTierIndex != _tierId - 1) continue;

                if (nodeOwner == _account) {
                    uint256 tierRewardsPerTime = tierArr[nodeTierIndex]
                        .rewardsPerTime;
                    uint256 tierClaimInterval = tierArr[nodeTierIndex]
                        .claimInterval;

                    uint256 multiplier = 1 ether;
                    claimableAmount =
                        (uint256(block.timestamp - nodeClaimedTime) *
                            tierRewardsPerTime *
                            multiplier) /
                        1 ether /
                        tierClaimInterval +
                        claimableAmount;

                    nodeIndiceResult[count] = nodeIndex;
                    count++;
                    if (_count != 0 && count == _count) break;
                }
            }
        }
        return (claimableAmount, count, nodeIndiceResult);
    }

    function burnUnPaidNodes() public onlyOwner {
        uint32[] memory unpaidNodesList = getUnpaidNodes();
        burnNodes(unpaidNodesList);
    }

    function swapTokensForEth(
        address _tokenAddress,
        address to,
        uint256 tokenAmount
    ) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        //_approve(address(this), address(uniswapV2Router), tokenAmount);
        IERC20(_tokenAddress).approve(
            address(uniswapV2Router),
            type(uint256).max
        );

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            to,
            block.timestamp
        );
    }
}

