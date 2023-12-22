// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { IERC165Upgradeable } from "./IERC165Upgradeable.sol";

import { OFTCoreUpgradeable } from "./OFTCoreUpgradeable.sol";
import { IOFTUpgradeable } from "./IOFTUpgradeable.sol";
import { ILayerZeroEndpoint } from "./ILayerZeroEndpoint.sol";

import { SingleLinkedList, SingleLinkedListLib } from "./SingleLinkedList.sol";

// import "hardhat/console.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address);
}

// later:
// TODO referrals
// TODO add permits?

contract OmnisCogitationisALT is OFTCoreUpgradeable, IERC20Upgradeable {

    using SingleLinkedListLib for SingleLinkedList;

    /* -------------------------------------------------------------------------- */
    /*                                   events                                   */
    /* -------------------------------------------------------------------------- */
    error InvalidParameters();
    error RemoteStateOutOfSync(uint remoteState);
    error ERC20InsufficientAllowance(address, address, uint);
    error InsuffcientBalance(uint);
    error OFTCoreUnknownPacketType();

    event Reflect(uint256 baseAmountReflected, uint256 totalNonReflected);
    event LaunchFee(address user, uint amount);

    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    string constant _name = "Omnis Cogitationis TEST";
    string constant _symbol = "OCG TEST";

    // TODO update

    // --- BSC (Pancake)
    // IUniswapV2Router02 public constant UNISWAP_V2_ROUTER = 
    //     IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // --- Polygon (Quickswap)
    // IUniswapV2Router02 public constant UNISWAP_V2_ROUTER = 
    //     IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff); 

    // --- Fantom (Spookyswap)
    // IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
    //     IUniswapV2Router02(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    // --- Arbitrum (Sushiswap)
    IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;

    uint256 constant MAX_FEE = 1_500; /* 15% */
    uint256 constant MAX_BP = 10_000;

    // uint256 constant LAUNCH_FEE = 0;

    uint16 public constant PT_TRANSMIT_AND_REQUEST = 1;
    uint16 public constant PT_TRANSMIT = 2;
    uint16 public constant PT_RESPONSE = 3;

    /* -------------------------------------------------------------------------- */
    /*                                   states                                   */
    /* -------------------------------------------------------------------------- */

    struct Fee {

        // to be swapped to native
        uint8 omnichain; /* used to cover gas for transmitting reflections across chains */
        uint8 buyback;
        uint8 referral; /* 50% user buying free reduction & 50% to referrer */

        // sent off
        uint8 marketing;
        uint8 lp; /* local LP + chain expansion */
        uint8 treasury;

        // not to be swapped to native
        uint8 reflection;
        uint8 burn;

        uint128 total;
    }

    // L0 chain IDs sorted by avg gas costs in decreasing order
    SingleLinkedList public chains;

    uint16 private lzChainId;

    uint256 public isClaimingFees;
    uint256 public swapThreshold;
    uint256 public totalNonReflected;

    uint256 private _totalSupply;
    uint256 private isInSwap;
    uint256 private isLowGasChain;
    uint256 private launchTime;
    uint256 private launchFeeDuration;

    address private _uniswapPair;
    // could pack & read those more tightly
    address private marketingFeeReceiver;
    address private lpFeeReceiver;
    address private buybackFeeReceiver;
    address private treasuryReceiver;

    Fee public buyFee;
    Fee public sellFee;

    mapping(address => uint256) public isRegistredPool; /* registred pools are excluded from receiving reflections */
    mapping(address => uint256) private _baseBalance;

    mapping(address => mapping(address => uint256)) private _allowances;

    constructor() {}

    receive() external payable {}

    function initialize(
        uint shareInBpToMint,
        address _lzEndpoint,
        address newMarketingFeeReceiver,
        address newLPfeeReceiver,
        address newBuyBackFeeReceiver,
        address newTreasuryReceiver
    ) public payable initializer {

        // initialise parents
        __Ownable_init_unchained();
        __LzAppUpgradeable_init_unchained(_lzEndpoint);

        // set variables
        launchTime = block.timestamp;
        launchFeeDuration = 10 days;

        _totalSupply = 1_000_000_000 ether;
        totalNonReflected = _totalSupply;

        swapThreshold = _totalSupply * 20 / MAX_BP; /* 0.2% of total supply */

        lzChainId = ILayerZeroEndpoint(_lzEndpoint).getChainId() + 100;
        chains.addNode(lzChainId, 0);

        marketingFeeReceiver = newMarketingFeeReceiver;
        lpFeeReceiver = newLPfeeReceiver;
        buybackFeeReceiver = newBuyBackFeeReceiver;
        treasuryReceiver = newTreasuryReceiver;
        
        buyFee = Fee({
            reflection: 100,
            omnichain:  100,
            buyback:    100,
            marketing:  100,
            lp:         100,
            treasury:   100,
            referral:     0,
            burn:         0,
            total:      600
        });
        sellFee = Fee({
            reflection: 100,
            omnichain:  100,
            buyback:    100,
            marketing:  100,
            lp:         100,
            treasury:   100,
            referral:     0,
            burn:         0,
            total:      600
        });

        // create uniswap pair
        _uniswapPair = IUniswapV2Factory(
            UNISWAP_V2_ROUTER.factory()
        ).createPair(address(this), UNISWAP_V2_ROUTER.WETH());
        
        // register pool as trading pool
        isRegistredPool[_uniswapPair] = 1;
        
        // set unlimited allowance for uniswap router
        _allowances[address(this)][address(UNISWAP_V2_ROUTER)] = type(uint256).max;

        // mint initial share to owner
        _baseBalance[tx.origin] = _totalSupply * shareInBpToMint / MAX_BP; 
        emit Transfer(address(0), tx.origin, _totalSupply);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    ERC20                                   */
    /* -------------------------------------------------------------------------- */
    
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            if(_allowances[sender][msg.sender] < amount) 
                revert ERC20InsufficientAllowance(sender, recipient, _allowances[sender][msg.sender]);
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }

        return _transferFrom(sender, recipient, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     OFT                                    */
    /* -------------------------------------------------------------------------- */

    function token() external view override returns (address) {
        return address(this);
    }

    function _debitFrom(
        address _from,
        uint16 /* dst chain id */,
        bytes memory /* toAddress */,
        uint _amount
    ) internal override returns (uint) {
        if (_from != msg.sender) {
            if (_allowances[_from][msg.sender] < _amount)
                revert ERC20InsufficientAllowance(_from, msg.sender, _amount);

            unchecked {
                _allowances[_from][msg.sender] = _allowances[_from][msg.sender] - _amount;
            }
        }

        if (_baseBalance[_from] < _amount)
            revert InsuffcientBalance(_amount);

        unchecked {
            // burn
            _baseBalance[_from] = _baseBalance[_from] - _amount;
        }
        return _amount;
    }

    function _creditTo(
        uint16 /* src chain id */,
        address _toAddress,
        uint _amount
    ) internal override returns (uint) {
        // mint
        _baseBalance[_toAddress] = _baseBalance[_toAddress] + _amount;
        return _amount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Views                                   */
    /* -------------------------------------------------------------------------- */
    
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(OFTCoreUpgradeable) returns (bool) {
        return
            interfaceId == type(IOFTUpgradeable).interfaceId ||
            interfaceId == type(IERC20Upgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return baseToReflectionAmount(_baseBalance[account], account);
    }

    function allowance(
        address holder,
        address spender
    ) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    function baseToReflectionAmount(
        uint256 baseAmount,
        address account
    ) public view returns (uint256) {
        return 
            isRegistredPool[account] != 0
            ? baseAmount
            : baseAmount * _totalSupply / (totalNonReflected - _baseBalance[_uniswapPair]);
    }

    function circulatingSupply() public view returns (uint256) {
        // TODO can maybe only use one burn address?
        return _totalSupply - balanceOf(DEAD) - balanceOf(ZERO);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Access restricted                            */
    /* -------------------------------------------------------------------------- */
    
    function clearStuckBalance() external payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function clearStuckToken() external payable onlyOwner {
        _transferFrom(address(this), msg.sender, balanceOf(address(this)));
    }

    function setSwapBackSettings(
        uint256 _enabled /* 0 = false, 1 = true */,
        uint256 _amount
    ) external payable onlyOwner {
        isClaimingFees = _enabled;
        swapThreshold = _amount;
    }

    function changeFees(
        uint8 reflectionFeeBuy,
        uint8 marketingFeeBuy,
        uint8 omnichainFeeBuy,
        uint8 treasuryFeeBuy,
        uint8 referralFeeBuy,
        uint8 lpFeeBuy,
        uint8 buybackFeeBuy,
        uint8 burnFeeBuy,

        uint8 reflectionFeeSell,
        uint8 marketingFeeSell,
        uint8 lpFeeSell,
        uint8 buybackFeeSell,
        uint8 burnFeeSell,
        uint8 omnichainFeeSell,
        uint8 treasuryFeeSell,
        uint8 referralFeeSell
    ) external payable onlyOwner {
        uint128 totalBuyFee = 
            reflectionFeeBuy +
            marketingFeeBuy +
            omnichainFeeBuy +
            treasuryFeeBuy +
            referralFeeBuy +
            lpFeeBuy +
            buybackFeeBuy +
            burnFeeBuy;
        uint128 totalSellFee = 
            reflectionFeeSell +
            marketingFeeSell +
            omnichainFeeSell +
            treasuryFeeSell +
            referralFeeSell +
            lpFeeSell +
            buybackFeeSell +
            burnFeeSell;

        if (totalBuyFee > MAX_FEE || totalSellFee > MAX_FEE)
            revert InvalidParameters();

        // TODO
        buyFee = Fee({
            reflection: reflectionFeeBuy,
            marketing: reflectionFeeBuy,
            omnichain: omnichainFeeBuy,
            treasury: treasuryFeeBuy,
            referral: referralFeeBuy,
            lp: reflectionFeeBuy,
            buyback: reflectionFeeBuy,
            burn: burnFeeBuy,
            total: totalBuyFee
        });

        sellFee = Fee({
            reflection: reflectionFeeSell,
            marketing: reflectionFeeSell,
            omnichain: omnichainFeeSell,
            treasury: treasuryFeeSell,
            referral: referralFeeSell,
            lp: reflectionFeeSell,
            buyback: reflectionFeeSell,
            burn: burnFeeSell,
            total: totalSellFee
        });
    }

    function setFeeReceivers(
        address newMarketingFeeReceiver,
        address newLPfeeReceiver,
        address newBuybackFeeReceiver,
        address newTreasuryReceiver
    ) external payable onlyOwner {
        marketingFeeReceiver = newMarketingFeeReceiver;
        lpFeeReceiver = newLPfeeReceiver;
        buybackFeeReceiver = newBuybackFeeReceiver;
        treasuryReceiver = newTreasuryReceiver;
    }

    function setTrustedRemoteWithInfo(
        uint16 _remoteChainId,
        bytes calldata _remoteAddress,
        uint8 chainListPosition
    ) external payable onlyOwner {
        // we only add the chain to the list of lower gas chains if it actually is a lower gas chain
        if(chainListPosition != 0) {
            chains.addNode(_remoteChainId, chainListPosition);
        }
        trustedRemoteLookup[_remoteChainId] = abi.encodePacked(_remoteAddress, address(this));
        emit SetTrustedRemoteAddress(_remoteChainId, _remoteAddress);
    }

    function setRegistredPool(address pool, uint state) external payable onlyOwner {
        isRegistredPool[pool] = state;
    }

    function removeChain(uint data) external payable onlyOwner {
        chains.removeNode(data);
    }

    // // TODO debugging only
    function getBeheadedList() external view returns(uint[] memory) {
        return chains.getBeheadedList();
    }

    
    /* -------------------------------------------------------------------------- */
    /*                                   Internal                                 */
    /* -------------------------------------------------------------------------- */
    
    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {

        uint256 baseAmount = 
            isRegistredPool[sender] != 0
            ? amount
            : amount * (totalNonReflected - _baseBalance[_uniswapPair]) / _totalSupply;

        if(_baseBalance[sender] < baseAmount) revert InsuffcientBalance(_baseBalance[sender]);

        // perform basic swap
        if (isInSwap != 0) {
            _baseBalance[sender] = _baseBalance[sender] - baseAmount;
            _baseBalance[recipient] = _baseBalance[recipient] + baseAmount;
            emit Transfer(sender, recipient, amount);
            return true;
        }

        // Swap own token balance against pool if conditions are fulfilled
        { // wrap into block since it's agnostic to stack
            if (
                isRegistredPool[msg.sender] == 0 && // this only swaps if it's not a buy, amplifying sells and leaving buys untouched
                isClaimingFees != 0 &&
                _baseBalance[address(this)] * _totalSupply / totalNonReflected /* balanceOf(address(this)) */ >= swapThreshold
            ) {
                isInSwap = 1;

                Fee memory memorySellFee = sellFee;

                uint256 stack_SwapThreshold = swapThreshold;
                uint256 amountToBurn = stack_SwapThreshold * memorySellFee.burn / memorySellFee.total;
                uint256 amountToSwap = stack_SwapThreshold - amountToBurn;

                // burn, no further checks needed here
                _baseBalance[address(this)] = _baseBalance[address(this)] - amountToBurn;
                _baseBalance[DEAD] = _baseBalance[DEAD] + amountToBurn;

                // swap non-burned tokens to ETH
                address[] memory path = new address[](2);
                path[0] = address(this);
                path[1] = UNISWAP_V2_ROUTER.WETH();

                UNISWAP_V2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    amountToSwap,
                    0, // TODO getAmountsOut
                    path,
                    address(this),
                    block.timestamp
                );
                
                uint256 amountETH = address(this).balance;

                // add up all the fees which should be swapped into ETH
                uint256 totalSwapShare = memorySellFee.total - memorySellFee.reflection - memorySellFee.burn;

                /* 
                 * send proceeds to respective wallets, except for omnichain
                 * we don't need to use return values of low level calls here since we can just manually withdraw
                 * funds in case of failure; receiver wallets are owner supplied though and should only be EOAs
                 * anyway
                 */

                // marketing
                payable(marketingFeeReceiver).call{value: amountETH * memorySellFee.marketing / totalSwapShare}("");
                // LP
                payable(lpFeeReceiver).call{value: amountETH * memorySellFee.lp / totalSwapShare}("");
                // buyback
                payable(buybackFeeReceiver).call{value: amountETH * memorySellFee.buyback / totalSwapShare}("");
                // treasury
                payable(treasuryReceiver).call{value: amountETH * memorySellFee.treasury / totalSwapShare}("");

                isInSwap = 0;
            }
        }

        // console.log("From", _baseBalance[sender]);

        uint256 baseAmountReceived = 
            isClaimingFees != 0
            ? _performReflectionAndTakeFees(baseAmount, sender, isRegistredPool[sender] != 0)
            : baseAmount;

        _baseBalance[sender] = _baseBalance[sender] - baseAmount;
        _baseBalance[recipient] = _baseBalance[recipient] + baseAmountReceived;
        emit Transfer(sender, recipient, baseToReflectionAmount(baseAmountReceived, recipient));

        return true;
    }

    function _performReflectionAndTakeFees(
        uint256 baseAmount,
        address sender,
        bool buying
    ) internal returns (uint256) {

        Fee memory memoryBuyFee = buyFee;
        Fee memory memorySellFee = sellFee;
        uint launchFeeAmount;

        // take launch fee
        // if(!buying && block.timestamp - launchTime < launchFeeDuration)  {
        //     isInSwap = 1;

        //     // swap back
        //     address[] memory path = new address[](2);
        //     path[0] = address(this);
        //     path[1] = UNISWAP_V2_ROUTER.WETH();

        //     launchFeeAmount = baseAmount * LAUNCH_FEE * (launchFeeDuration - (block.timestamp - launchTime)) / launchFeeDuration / MAX_BP;

        //     _baseBalance[address(this)] = _baseBalance[address(this)] + launchFeeAmount;

        //     uint reflectedLaunchFeeAmount = baseToReflectionAmount(launchFeeAmount, address(this));
        //     emit Transfer(sender, address(this), reflectedLaunchFeeAmount);
        //     emit LaunchFee(sender, reflectedLaunchFeeAmount);

        //     UNISWAP_V2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
        //         reflectedLaunchFeeAmount,
        //         0, // TODO getAmountsOut
        //         path,
        //         treasuryReceiver,
        //         block.timestamp
        //     );

        //     isInSwap = 0;
        // }        

        // amount of fees in base amount (non-reflection adjusted)
        uint256 baseFeeAmount = 
            buying
            ? baseAmount * memoryBuyFee.total / MAX_BP
            : baseAmount * memorySellFee.total / MAX_BP;

        // reflect
        uint256 baseAmountReflected = 
            buying
            ? baseAmount * memoryBuyFee.reflection / MAX_BP
            : baseAmount * memorySellFee.reflection / MAX_BP;

        /** 
         * Omnichain
         * 
         * - integrate local delta into state
         * - send local delta to lower gas chains
         * - request local state from lowest gas chain
         * - set local state to minimum (=most recent) of local state & remote state
         */
        totalNonReflected = totalNonReflected - baseAmountReflected;
        emit Reflect(baseAmountReflected, totalNonReflected);
        _transmitReflectionToOtherChainsAndFetchState(baseAmountReflected);

        // add entire non-reflected amount to contract balance for later swapping
        uint256 baseBalanceToContract = baseFeeAmount - baseAmountReflected;
        if (baseBalanceToContract != 0) {
            _baseBalance[address(this)] = _baseBalance[address(this)] + baseBalanceToContract;
            emit Transfer(sender, address(this), baseToReflectionAmount(baseBalanceToContract, address(this)));
        }

        return baseAmount - baseFeeAmount - launchFeeAmount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                     L0                                     */
    /* -------------------------------------------------------------------------- */

    /** @notice Multicast reflection state change to all chains that are tendencially
     * cheaper than the local chain & fetch reflection state of cheapest chain to
     * integrate into local state
     * @param delta amount reflected by this transaction that is to be multicasted
     */
    function _transmitReflectionToOtherChainsAndFetchState(
        uint256 delta
    ) internal {

        if(chains.length < 2) return;

        uint256[] memory lowerGasChains = chains.getBeheadedList();
        uint256 lowerGasChainsLen = lowerGasChains.length;

        bytes memory lzPayload = abi.encode(PT_TRANSMIT, delta);

        // TODO update
        uint256 gasUsage = 1_000_000; 

        for (uint iterator; iterator < lowerGasChainsLen - 1; ) {
            // TODO how much gas does this view cost? would it be cheaper to let the call fail in a try/catch?

            (uint gasRequired, /* zroFee */) = lzEndpoint.estimateFees(
                uint16(lowerGasChains[iterator]),
                address(this),
                lzPayload,
                false,
                abi.encodePacked(uint16(1), gasUsage)
            );

            if (address(this).balance > gasRequired) {
                _lzSend(
                    // cheapest chain
                    uint16(lowerGasChains[iterator]), // destination chainId
                    lzPayload, // abi.encode()'ed bytes
                    payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
                    address(0x0), // future param, unused for this example
                    abi.encodePacked(uint16(1), gasUsage), // v1 adapterParams, specify custom destination gas qty
                    address(this).balance
                );
                unchecked { iterator = iterator + 1; }
            } else {
                // abort transmissions if gas is insufficient
                return;
            }
        }

        uint256 lowestGasChainId = lowerGasChains[lowerGasChainsLen - 1];
        if (lzChainId != lowestGasChainId) {
            lzPayload = abi.encode(PT_TRANSMIT_AND_REQUEST, delta);

            (uint gasRequired, /* zroFee */) = lzEndpoint.estimateFees(
                uint16(lowestGasChainId),
                address(this),
                lzPayload,
                false,
                abi.encodePacked(uint16(1), gasUsage)
            );

            // TODO how much gas does this view cost? would it be cheaper to let the call fail in a try/catch?
            if (address(this).balance > gasRequired) {
                // fetch the state from the lowest gas chain
                _lzSend(
                    uint16(lowestGasChainId), // destination chainId
                    lzPayload, // abi.encode()'ed bytes
                    payable(this), // refund address
                    address(0x0), // future param, unused for this example
                    abi.encodePacked(uint16(1), gasUsage), // v1 adapterParams, specify custom destination gas qty
                    address(this).balance
                );
            }
        }
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        uint16 packetType;
        assembly {
            packetType := mload(add(_payload, 32))
        }

        if (packetType == PT_SEND) {
            // token transfers between chains
            _sendAck(_srcChainId, _srcAddress, _nonce, _payload);
        } else if (packetType == PT_TRANSMIT_AND_REQUEST) {
            _receiveReflectionUpdate(_srcChainId, _payload, true /* is request? */);
        } else if (packetType == PT_TRANSMIT) {
            _receiveReflectionUpdate(_srcChainId, _payload, false /* is request? */);
        } else if (packetType == PT_RESPONSE) {
            _receiveRemoteReflectionState(_payload);
        } else {
            revert OFTCoreUnknownPacketType();
        }
    }

    function _receiveReflectionUpdate(
        uint16 _srcChainId,
        bytes memory _payload,
        bool isReq
    ) internal {

        // TODO extract payload more efficiently with assembly
        (/* packet type */, uint delta) = abi.decode(_payload, (uint16, uint));

        // update local reflection data
        totalNonReflected = totalNonReflected - delta;
        emit Reflect(delta, totalNonReflected);

        // transmission comes from higher gas chain that wants to know local state
        if(isReq) {

            // pack payload AFTER integrating remote delta
            bytes memory lzPayload = abi.encode(PT_RESPONSE, totalNonReflected);

            uint originChainGasUsage = 1_000_000;

            // send response to origin chain
            _lzSend(
                _srcChainId, // destination chainId
                lzPayload, // abi.encode()'ed bytes
                payable(this), // (msg.sender will be this contract) refund address
                address(0x0), // future param, unused for this example
                abi.encodePacked(uint16(1), originChainGasUsage), // v1 adapterParams, specify custom destination gas qty
                address(this).balance
            );
        }
    }

    /**
     * @notice receive response to a request made to the lowest gas chain
     * @param _payload contains (uint16 packetType, uint256 remoteReflectionState)
     */
    function _receiveRemoteReflectionState(bytes memory _payload) internal {
        // TODO extract payload more efficiently with assembly
        (/* packet type */, uint remoteReflectionState) = abi.decode(_payload, (uint16, uint));

        /**
         * This should not happen since remote chain integrates local changes before sending response
         * and hence can never be greater than local state ... should it happen, apply some error
         * handling here.
         */
        // TODO error handling, resend local state & request remote state again
        if (remoteReflectionState > totalNonReflected)
            revert RemoteStateOutOfSync(remoteReflectionState);

        // integrate remote changes if they are more recent than local state (=smaller value)
        uint reflectionStateDiff = totalNonReflected - remoteReflectionState;
        if (reflectionStateDiff != 0) {
            totalNonReflected = remoteReflectionState;
            emit Reflect(reflectionStateDiff, remoteReflectionState);
        }
    }

}
