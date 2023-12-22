// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./console.sol";

contract Staking is ReentrancyGuard, Ownable {
    /**
     * 质押实例的结构定义
     */
    struct FlexiblePlan {
        /**
         * 质押的代币
         */
        string token;
        /**
         * 每秒的利率
         * 例如年化利率是10%，得出每秒利率就是0.1/365/24/60/60=0.000000003170979
         */
        uint256 ratePerSecond;
        /**
         * 用户可参与的最小数量
         */
        uint256 minQuantityPerUser;
        /**
         * 用户可参与的最大数量
         */
        uint256 maxQuantityPerUser;
        /**
         * 总计可质押的最大代币量
         */
        uint256 maxStakeableQuantity;
        /**
         * 结束日期
         */
        uint256 endDate;
        /**
         * 已质押的代币总量
         */
        uint256 totalStaked;
    }

    /**
     * 用于存储所有可质押的活动
     */
    struct Plans {
        FlexiblePlan[] flexiblePlans;
    }

    /**
     * 用户质押的结构定义
     */
    struct UserFlexiblePlan {
        /**
         * 质押的代币
         */
        string token;
        /**
         * 每秒的利率
         */
        uint256 ratePerSecond;
        /**
         * 质押的数量
         */
        uint256 quantity;
        /**
         * 开始日期
         */
        uint256 startDate;
        /**
         * 结束日期
         */
        uint256 endDate;
        /**
         * 累积的利息
         */
        uint256 interestAccumulated;
        /**
         * 是否处于活动状态
         */
        bool active;
    }

    /**
     * 保存质押过的用户
     */
    struct Stakeholder {
        /**
         * 用户地址
         */
        address userAddr;
        /**
         * 用户质押活动列表
         */
        UserFlexiblePlan[] flexiblePlans;
    }

    /**
     * 指定代币与合约地址的关系
     * 通过代币名称可以查找到合约地址
     */
    mapping(string => address) public mapTokenPair;
    /**
     * 用户质押活动的关系
     * 可以通过用户地址和质押活动ID，查找到质押活动细节
     */
    mapping(address => mapping(uint256 => uint256)) mapUserPlanIdToFlexiblePlanIndex;
    /**
     * 用户与 质押活动Id 的关系
     * 通过用户地址，可以检索到 stakeholders 中用户参与的质押活动列表
     */
    mapping(address => uint256) addressToStakeholderIndex;

    /**
     * 质押的计划列表
     */
    Plans private plans;

    /**
     * 存储质押过的用户数组
     */
    Stakeholder[] private stakeholders;

    /**
     * 初始化构造函数
     */
    constructor() {
        // 初始化数组，索引值为0没有任何数据
        stakeholders.push();
        plans.flexiblePlans.push();
    }

    /**
     * 添加代币和地址
     */
    function AddTokenPair(string memory token_, address _contractAddress)
        external
        onlyOwner
    {
        mapTokenPair[token_] = _contractAddress;
    }

    /**
     * 创建质押计划
     * @param token_ 质押的代币名称
     * @param ratePerSecond_ 每秒的利率
     * @param minQuantityPerUser_ 用户可参与的最小数量
     * @param maxQuantityPerUser_ 用户可参与的最大数量
     * @param maxStakeableAmount_ 质押池总数量
     * @param endDate_ 结束日期
     */
    function CreateFlexibleStakingPlan(
        string memory token_,
        uint256 ratePerSecond_,
        uint256 minQuantityPerUser_,
        uint256 maxQuantityPerUser_,
        uint256 maxStakeableAmount_,
        uint256 endDate_
    ) external onlyOwner {
        require(mapTokenPair[token_] != address(0x00), "token is not added");

        require(
            endDate_ > block.timestamp,
            "end date cannot be earlier than the current date"
        );

        // 将空数组添加到质押活动列表
        plans.flexiblePlans.push();

        // 获取最新添加的空数组
        uint256 index = SafeMath.sub(plans.flexiblePlans.length, 1);

        // 向数组中设置值
        plans.flexiblePlans[index] = FlexiblePlan(
            token_,
            ratePerSecond_,
            minQuantityPerUser_,
            maxQuantityPerUser_,
            maxStakeableAmount_,
            endDate_,
            0
        );
    }

    /**
     * 质押代币
     * @param planId_ 质押计划ID
     * @param quantity_ 质押数量
     */
    function StakeInFlexiblePlan(uint256 planId_, uint256 quantity_) external {
        // planId 不能超过活动数组长度
        require(planId_ < plans.flexiblePlans.length, "invalid plan ID");

        // 获取当前时间
        uint256 currentTime = block.timestamp;

        // read only
        // 获取质押活动
        FlexiblePlan memory flexiblePlan = plans.flexiblePlans[planId_];

        // 是否过期
        require(flexiblePlan.endDate > currentTime, "plan is expired");

        // 质押数量不能小于要求的最小数量
        require(
            quantity_ >= flexiblePlan.minQuantityPerUser,
            "minimum quantity per user criteria not met"
        );

        // 质押数量 + 已质押总量，不能大于质押池最大数量
        require(
            flexiblePlan.maxStakeableQuantity >=
                flexiblePlan.totalStaked + quantity_,
            "maximum stakeable quantity exceeds"
        );

        // 获取参与的质押活动索引
        uint256 index = addressToStakeholderIndex[msg.sender];

        // 如果不存在，添加一个
        if (index == 0) {
            // doesn't exist, add
            index = AddStakeholder(msg.sender);
        }

        // 获取用户质押活动计划的索引
        uint256 userPlanIndex = mapUserPlanIdToFlexiblePlanIndex[msg.sender][
            planId_
        ];

        // read only
        // 获取用户对 planId_ 已质押的数据
        UserFlexiblePlan memory userFlexiblePlan = stakeholders[index]
            .flexiblePlans[userPlanIndex];

        // 用户已质押数量 + 本次质押数量，不能大于用户最大质押数量
        require(
            userFlexiblePlan.quantity + quantity_ <=
                flexiblePlan.maxQuantityPerUser,
            "maximum quantity per user criteria not met"
        );

        // 调用质押 ERC20 代币
        IERC20 contractAddr = IERC20(mapTokenPair[flexiblePlan.token]);

        // 向质押合约转入指定数量代币
        contractAddr.transferFrom(msg.sender, address(this), quantity_);

        // 如果用户已质押过的数量 + 利息大于 0
        // 说明用户之前参与过质押
        if (
            SafeMath.add(
                userFlexiblePlan.quantity,
                userFlexiblePlan.interestAccumulated
            ) > 0
        ) {
            // 获取已经质押过的利息
            uint256 totalInterest = GetTotalInterestFlexiblePlan(
                msg.sender,
                planId_
            );

            // 更新质押活动的利息
            userFlexiblePlan.interestAccumulated = totalInterest;

            // 累加用户质押的数量
            userFlexiblePlan.quantity = SafeMath.add(
                userFlexiblePlan.quantity,
                quantity_
            );

            // 重新设置用户参与的时间
            userFlexiblePlan.startDate = currentTime;

            // 更新参与质押活动的用户里面，用户活动计划索引的内容
            stakeholders[index].flexiblePlans[userPlanIndex] = userFlexiblePlan;
        } else {
            // 用户第一次参与这个活动的质押，添加新结构到索引
            stakeholders[index].flexiblePlans.push(
                UserFlexiblePlan(
                    flexiblePlan.token,
                    flexiblePlan.ratePerSecond,
                    quantity_,
                    currentTime,
                    flexiblePlan.endDate,
                    0,
                    true
                )
            );

            // 存储 用户地址与质押活动planId_ 的内容为 最新添加的用户活动索引
            mapUserPlanIdToFlexiblePlanIndex[msg.sender][planId_] = SafeMath
                .sub(stakeholders[index].flexiblePlans.length, 1);
        }

        // 更新质押活动列表中的总质押数量 加上此次用户质押的数量
        plans.flexiblePlans[planId_].totalStaked = SafeMath.add(
            flexiblePlan.totalStaked,
            quantity_
        );
    }

    /**
     * 解除质押
     * @param planId_ 质押活动Id
     * @param quantity_ 解除的数量
     */
    function UnstakeInFlexiblePlan(uint256 planId_, uint256 quantity_)
        external
        nonReentrant
    {
        // 获取用户在 stakeholders 中的索引位置
        uint256 index = addressToStakeholderIndex[msg.sender];

        // 如果 index=0,说明用户未质押过，抛出异常
        require(
            index > 0,
            "only stakers are allowed to perform this operation"
        );

        // 获取当前时间
        uint256 currentTime = block.timestamp;

        // 获取已添加的质押计划
        FlexiblePlan memory flexiblePlan = plans.flexiblePlans[planId_];

        // 获取用户与质押活动的索引
        uint256 userPlanIndex = mapUserPlanIdToFlexiblePlanIndex[msg.sender][
            planId_
        ];

        // 从已质押中查找用户质押的计划
        UserFlexiblePlan memory userFlexiblePlan = stakeholders[index]
            .flexiblePlans[userPlanIndex];

        // 如果 active 为false 抛出异常
        require(
            userFlexiblePlan.active == true,
            "user stake plan is not active"
        );

        // 计算当前质押收益
        uint256 totalInterest = GetTotalInterestFlexiblePlan(
            msg.sender,
            planId_
        );
        // 转出的数量
        uint256 withdrawableQty;

        // 如果用户质押活动结束日期小于当前时间,说明已过期
        if (userFlexiblePlan.endDate <= currentTime) {
            // 更新用户质押活动的利息
            userFlexiblePlan.interestAccumulated = totalInterest;

            // 转出数量 = 用户投入的数量 + 利息
            withdrawableQty = SafeMath.add(
                userFlexiblePlan.quantity,
                userFlexiblePlan.interestAccumulated
            );

            // 解除质押的数量不能大于转出数量
            require(
                quantity_ <= withdrawableQty,
                "unstaked amount is incorrect"
            );

            // 设置用户当前质押活动失效
            userFlexiblePlan.active = false;
        } else {
            // plan is not expired, user can only unstake deposited quantity
            withdrawableQty = quantity_;
            require(
                quantity_ <= userFlexiblePlan.quantity,
                "the unstaked amount is greater than the pledged amount"
            );

            // 减掉解除质押的数量
            userFlexiblePlan.quantity = SafeMath.sub(
                userFlexiblePlan.quantity,
                quantity_
            );

            // 更新质押日期
            userFlexiblePlan.startDate = currentTime;

            // 更新质押利息
            userFlexiblePlan.interestAccumulated = totalInterest;

            // 从总的质押活动中减掉相应的数量
            plans.flexiblePlans[planId_].totalStaked = SafeMath.sub(
                plans.flexiblePlans[planId_].totalStaked,
                quantity_
            );
        }

        // 获取用户质押的合约实例
        IERC20 contractAddr = IERC20(mapTokenPair[flexiblePlan.token]);

        // 将合约中的代币转出给解除质押的用户
        contractAddr.transfer(msg.sender, withdrawableQty);

        // 更新用户质押活动的数据结构
        stakeholders[index].flexiblePlans[userPlanIndex] = userFlexiblePlan;
    }

    /**
     * 将用户地址添加到已质押列表
     */
    function AddStakeholder(address address_) private returns (uint256) {
        // 添加一个空元素到已质押用户数组
        stakeholders.push();

        // 获取新添加的索引
        uint256 userIndex = SafeMath.sub(stakeholders.length, 1);

        // 设置新数组的用户地址
        stakeholders[userIndex].userAddr = address_;

        // 添加一个空元素到用户参与的质押计划
        stakeholders[userIndex].flexiblePlans.push();

        // 添加用户和质押过的索引到map
        addressToStakeholderIndex[address_] = userIndex;

        // 返回索引
        return userIndex;
    }

    /**
     * 读取用户质押的数据信息
     */
    function GetStakeholder(address address_)
        external
        view
        returns (Stakeholder memory)
    {
        uint256 index = addressToStakeholderIndex[address_];
        return stakeholders[index];
    }

    /**
     * 获取所有质押活动
     */
    function GetPlans() external view returns (Plans memory) {
        return plans;
    }

    /**
     * 计算利息
     * @param address_ 用户地址
     * @param planId_ 质押活动Id
     */
    function GetTotalInterestFlexiblePlan(address address_, uint256 planId_)
        public
        view
        returns (uint256)
    {
        // 获取当前时间
        uint256 currentTime = block.timestamp;

        // 获取用户质押活动的索引
        uint256 userPlanIndex = mapUserPlanIdToFlexiblePlanIndex[address_][
            planId_
        ];

        // 获取用户在 stakeholders 中的索引位置
        uint256 index = addressToStakeholderIndex[address_];

        // 获取用户参与质押活动的数据
        UserFlexiblePlan memory userFlexiblePlan = stakeholders[index]
            .flexiblePlans[userPlanIndex];

        // 如果活动已结束，直接返回利息
        if (!userFlexiblePlan.active) {
            return userFlexiblePlan.interestAccumulated;
        }

        // 当前利息
        uint256 currentAccumulatedInterest = 0;

        // 日期已过期
        if (currentTime >= userFlexiblePlan.endDate) {
            // 利息 = (用户活动计划的结束日期 - 开始日期) * 质押数量 * 每秒利率 /
            currentAccumulatedInterest = SafeMath.div(
                (
                    SafeMath.mul(
                        SafeMath.sub(
                            userFlexiblePlan.endDate,
                            userFlexiblePlan.startDate
                        ),
                        SafeMath.mul(
                            userFlexiblePlan.quantity,
                            userFlexiblePlan.ratePerSecond
                        )
                    )
                ),
                (10**20)
            );
        } else {
            // 利息 = (当前日期 - 开始日期) * 质押数量 * 每秒利率 /
            currentAccumulatedInterest = SafeMath.div(
                (
                    SafeMath.mul(
                        SafeMath.sub(currentTime, userFlexiblePlan.startDate),
                        SafeMath.mul(
                            userFlexiblePlan.quantity,
                            userFlexiblePlan.ratePerSecond
                        )
                    )
                ),
                (10**20)
            );
        }
        return
            currentAccumulatedInterest + userFlexiblePlan.interestAccumulated;
    }

    /**
     * 将合约中的代币转移给指定地址
     * @param token_ 合约地址
     * @param to_ 接收代币的用户
     */
    function StuckBalance(
        address token_,
        address to_,
        uint quantity_
    ) external onlyOwner {
        IERC20 token = IERC20(token_);
        token.transfer(to_, quantity_);
    }
}

