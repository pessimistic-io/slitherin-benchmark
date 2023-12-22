//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./KarrotInterfaces.sol";

/**
Manager for config variables

Notes:
- once operation is stable, timelock will be set as owner
- openKarrotChefDeposits: first stolen pool epoch (epoch 0) starts at the same time as the karrot chef deposits open
 */


contract ConfigManager is Ownable {
    //======================================================================================
    // setup
    //======================================================================================

    IRabbit public rabbit;
    IKarrotsToken public karrots;
    IStolenPool public stolenPool;
    IAttackRewardCalculator public rewardCalculator;
    IDexInterfacer public dexInterfacer;
    IKarrotChef public karrotChef;
    IFullProtec public karrotFullProtec;

    address public treasuryAddress; //(TESTING)main treasury
    address public treasuryBAddress; //(TESTING)funds from stolen funds pool
    address public sushiswapFactoryAddress; //arb one mainnet + eth goerli + fuji
    address public sushiswapRouterAddress; //arb one mainnet + eth goerli + fuji
    address public karrotsPoolAddress;
    address public timelockControllerAddress;
    address public karrotsAddress;
    address public karrotChefAddress;
    address public karrotFullProtecAddress;
    address public karrotStolenPoolAddress;
    address public rabbitAddress;
    address public randomizerAddress; //mainnet (arb one) 0x5b8bB80f2d72D0C85caB8fB169e8170A05C94bAF
    address public attackRewardCalculatorAddress;
    address public dexInterfacerAddress;
    address public presaleDistributorAddress; //testing is 0xFB1423Bf6b2CB13b4c86AA19AE4Bf266C9B36460
    address public teamSplitterAddress; //testing is 0x7639c5Fba3878f9717c90037bF0F355E40B49a6E

    constructor(
        address _treasuryAddress,
        address _treasuryBAddress,
        address _sushiswapFactoryAddress,
        address _sushiswapRouterAddress,
        address _randomizerAddress,
        address _presaleDistributorAddress,
        address _teamSplitterAddress
    ) {
        treasuryAddress = _treasuryAddress;
        treasuryBAddress = _treasuryBAddress;
        sushiswapFactoryAddress = _sushiswapFactoryAddress;
        sushiswapRouterAddress = _sushiswapRouterAddress;
        randomizerAddress = _randomizerAddress;
        presaleDistributorAddress = _presaleDistributorAddress;
        teamSplitterAddress = _teamSplitterAddress;
    }

    function transferOwnershipToTimelock() external onlyOwner {
        transferOwnership(timelockControllerAddress);
    }

    //======================================================================================
    // include setters for each "global" parameter --> gated by onlyOwner
    //======================================================================================

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setTreasuryBAddress(address _treasuryBAddress) external onlyOwner {
        treasuryBAddress = _treasuryBAddress;      
    }

    function setSushiFactoryAddress(address _sushiswapFactoryAddress) external onlyOwner {
        sushiswapFactoryAddress = _sushiswapFactoryAddress;        
    }

    function setSushiRouterAddress(address _sushiswapRouterAddress) external onlyOwner {
        sushiswapRouterAddress = _sushiswapRouterAddress;        
    }

    function setKarrotsPoolAddress(address _karrotsPoolAddress) external onlyOwner {
        karrotsPoolAddress = _karrotsPoolAddress;        
    }

    function setTimelockControllerAddress(address _timelockControllerAddress) external onlyOwner {
        timelockControllerAddress = _timelockControllerAddress;       
    }

    function setKarrotTokenAddress(address _karrotTokenAddress) external onlyOwner {
        karrotsAddress = _karrotTokenAddress;
        karrots = IKarrotsToken(_karrotTokenAddress);    
    }

    function setKarrotChefAddress(address _karrotChefAddress) external onlyOwner {
        karrotChefAddress = _karrotChefAddress;
        karrotChef = IKarrotChef(_karrotChefAddress);       
    }

    function setKarrotFullProtecAddress(address _fullProtecAddress) external onlyOwner {
        karrotFullProtecAddress = _fullProtecAddress;
        karrotFullProtec = IFullProtec(_fullProtecAddress);      
    }

    function setKarrotStolenPoolAddress(address _stolenPoolAddress) external onlyOwner {
        karrotStolenPoolAddress = _stolenPoolAddress;
        stolenPool = IStolenPool(_stolenPoolAddress);   
    }

    function setRabbitAddress(address _rabbitAddress) external onlyOwner {
        rabbitAddress = _rabbitAddress;
        rabbit = IRabbit(_rabbitAddress);       
    }

    function setRandomizerAddress(address _randomizerRequesterAddress) external onlyOwner {
        randomizerAddress = _randomizerRequesterAddress;        
    }

    function setRewardCalculatorAddress(address _rewardCalculatorAddress) external onlyOwner {
        attackRewardCalculatorAddress = _rewardCalculatorAddress;
        rewardCalculator = IAttackRewardCalculator(_rewardCalculatorAddress);       
    }

    function setDexInterfacerAddress(address _dexInterfacerAddress) external onlyOwner {
        dexInterfacerAddress = _dexInterfacerAddress;
        dexInterfacer = IDexInterfacer(_dexInterfacerAddress);      
    }

    function setPresaleDistributorAddress(address _presaleClaimContractAddress) external onlyOwner {
        presaleDistributorAddress = _presaleClaimContractAddress;      
    }

    function setTeamSplitterAddress(address _teamSplitterAddress) external onlyOwner {
        teamSplitterAddress = _teamSplitterAddress;     
    }

    //======================================================================================
    // NEW SETTERS FOR KARROTS CONFIG (CALLS FUNCTIONS ON KARROTS)
    //======================================================================================

    function setSellTaxIsActive(bool _sellTaxIsActive) external onlyOwner {
        karrots.setSellTaxIsActive(_sellTaxIsActive);
    }

    function setBuyTaxIsActive(bool _buyTaxIsActive) external onlyOwner {
        karrots.setBuyTaxIsActive(_buyTaxIsActive);
    }

    function setBuyTaxRate(uint16 _buyTaxRate) external onlyOwner {
        karrots.setBuyTaxRate(_buyTaxRate);
    }

    function setSellTaxRate(uint16 _sellTaxRate) external onlyOwner {
        karrots.setSellTaxRate(_sellTaxRate);
    }

    function setTradingIsOpen(bool _tradingIsOpen) external onlyOwner {
        karrots.setTradingIsOpen(_tradingIsOpen);
    }

    function addDexAddress(address _dexAddress) external onlyOwner {
        karrots.addDexAddress(_dexAddress);
    }

    //======================================================================================
    // NEW SETTERS FOR RABBIT (CALLS FUNCTIONS ON RABBIT)
    //======================================================================================

    function setRabbitMintIsOpen(bool _rabbitMintIsOpen) external onlyOwner {
        rabbit.setRabbitMintIsOpen(_rabbitMintIsOpen);
    }

    function setRabbitBatchSize(uint8 _rabbitBatchSize) external onlyOwner {
        rabbit.setRabbitBatchSize(_rabbitBatchSize);
    }

    function setRabbitMintSecondsBetweenBatches(uint32 _rabbitMintSecondsBetweenBatches) external onlyOwner {
        rabbit.setRabbitMintSecondsBetweenBatches(_rabbitMintSecondsBetweenBatches);
    }

    function setRabbitMaxPerWallet(uint8 _rabbitMaxPerWallet) external onlyOwner {
        rabbit.setRabbitMaxPerWallet(_rabbitMaxPerWallet);
    }

    function setRabbitMintPriceInKarrots(uint72 _rabbitMintPriceInKarrots) external onlyOwner {
        rabbit.setRabbitMintPriceInKarrots(_rabbitMintPriceInKarrots);
    }

    function setRabbitRerollPriceInKarrots(uint72 _rabbitRerollPriceInKarrots) external onlyOwner {
        rabbit.setRabbitRerollPriceInKarrots(_rabbitRerollPriceInKarrots);
    }

    function setRabbitMintKarrotFeePercentageToBurn(uint16 _rabbitMintKarrotFeePercentageToBurn) external onlyOwner {
        rabbit.setRabbitMintKarrotFeePercentageToBurn(_rabbitMintKarrotFeePercentageToBurn);
    }

    function setRabbitMintKarrotFeePercentageToTreasury(
        uint16 _rabbitMintKarrotFeePercentageToTreasury
    ) external onlyOwner {
        rabbit.setRabbitMintKarrotFeePercentageToTreasury(_rabbitMintKarrotFeePercentageToTreasury);
    }

    function setRabbitMintTier1Threshold(uint16 _rabbitMintTier1Threshold) external onlyOwner {
        rabbit.setRabbitMintTier1Threshold(_rabbitMintTier1Threshold);
    }

    function setRabbitMintTier2Threshold(uint16 _rabbitMintTier2Threshold) external onlyOwner {
        rabbit.setRabbitMintTier2Threshold(_rabbitMintTier2Threshold);
    }

    function setRabbitTier1HP(uint8 _rabbitTier1HP) external onlyOwner {
        rabbit.setRabbitTier1HP(_rabbitTier1HP);
    }

    function setRabbitTier2HP(uint8 _rabbitTier2HP) external onlyOwner {
        rabbit.setRabbitTier2HP(_rabbitTier2HP);
    }

    function setRabbitTier3HP(uint8 _rabbitTier3HP) external onlyOwner {
        rabbit.setRabbitTier3HP(_rabbitTier3HP);
    }

    function setRabbitTier1HitRate(uint16 _rabbitTier1HitRate) external onlyOwner {
        rabbit.setRabbitTier1HitRate(_rabbitTier1HitRate);
    }

    function setRabbitTier2HitRate(uint16 _rabbitTier2HitRate) external onlyOwner {
        rabbit.setRabbitTier2HitRate(_rabbitTier2HitRate);
    }

    function setRabbitTier3HitRate(uint16 _rabbitTier3HitRate) external onlyOwner {
        rabbit.setRabbitTier3HitRate(_rabbitTier3HitRate);
    }

    //call this EPOCH_LENGTH after opening deposits for KarrotChef! will revert otherwise...
    function setRabbitAttackIsOpen(bool _isOpen) external onlyOwner {
        stolenPool.setStolenPoolAttackIsOpen(_isOpen);
        rabbit.setRabbitAttackIsOpen(_isOpen);
    }

    function setAttackCooldownSeconds(uint32 _attackCooldownSeconds) external onlyOwner {
        rabbit.setAttackCooldownSeconds(_attackCooldownSeconds);
    }

    function setAttackHPDeductionAmount(uint8 _attackHPDeductionAmount) external onlyOwner {
        rabbit.setAttackHPDeductionAmount(_attackHPDeductionAmount);
    }

    function setAttackHPDeductionThreshold(uint16 _attackHPDeductionThreshold) external onlyOwner {
        rabbit.setAttackHPDeductionThreshold(_attackHPDeductionThreshold);
    }

    function setRandomizerMintCallbackGasLimit(uint24 _randomizerMintCallbackGasLimit) external onlyOwner {
        rabbit.setRandomizerMintCallbackGasLimit(_randomizerMintCallbackGasLimit);
    }

    function setRandomizerAttackCallbackGasLimit(uint24 _randomizerAttackCallbackGasLimit) external onlyOwner {
        rabbit.setRandomizerAttackCallbackGasLimit(_randomizerAttackCallbackGasLimit);
    }

    //======================================================================================
    // NEW SETTERS FOR KARROT CHEF (CALLS FUNCTIONS ON KARROT CHEF)
    //======================================================================================

    function setKarrotChefPoolAllocPoints(uint256 _pid, uint128 _allocPoints, bool _withUpdate) external onlyOwner {
        karrotChef.setAllocationPoint(_pid, _allocPoints, _withUpdate);
    }

    function setKarrotChefLockDuration(uint256 _pid, uint256 _lockDuration) external onlyOwner {
        karrotChef.setLockDuration(_pid, _lockDuration);
    }

    function updateKarrotChefRewardPerBlock(uint88 _karrotChefRewardPerBlock) external onlyOwner {
        karrotChef.updateRewardPerBlock(_karrotChefRewardPerBlock);
    }

    function setKarrotChefCompoundRatio(uint48 _compoundRatio) external onlyOwner {
        karrotChef.setCompoundRatio(_compoundRatio);
    }

    function openKarrotChefDeposits() external onlyOwner {
        karrotChef.openKarrotChefDeposits();
        stolenPool.setStolenPoolOpenTimestamp();
    }

    function setDepositIsPaused(bool _depositIsPaused) external onlyOwner {
        karrotChef.setDepositIsPaused(_depositIsPaused);
    }

    function setClaimTaxRate(uint16 _maxClaimTaxRate) external onlyOwner {
        karrotChef.setClaimTaxRate(_maxClaimTaxRate);
    }

    function setNumConfirmationsIsOn(bool _numConfirmationsIsOn) external onlyOwner {
        karrotChef.setNumConfirmationsIsOn(_numConfirmationsIsOn);
        rabbit.setNumConfirmationsIsOn(_numConfirmationsIsOn);
    }

    function setRandomizerClaimCallbackGasLimit(uint24 _randomizerCallbackGasLimit) external onlyOwner {
        karrotChef.setRandomizerClaimCallbackGasLimit(_randomizerCallbackGasLimit);
    }

    function setCallbackNumberOfConfirmations(uint8 _callbackNumberOfConfirmations) external onlyOwner {
        karrotChef.setCallbackNumberOfConfirmations(_callbackNumberOfConfirmations);
        rabbit.setCallbackNumberOfConfirmations(_callbackNumberOfConfirmations);
    }

    function setFullProtecLiquidityProportion(uint16 _fullProtecLiquidityProportion) external onlyOwner {
        karrotChef.setFullProtecLiquidityProportion(_fullProtecLiquidityProportion);
    }

    function setClaimTaxChance(uint16 _claimTaxChance) external onlyOwner {
        karrotChef.setClaimTaxChance(_claimTaxChance);
    }

    function withdrawRequestFeeFunds(address _to, uint256 _amount) external onlyOwner {
        karrotChef.randomizerWithdrawKarrotChef(_to, _amount);
        rabbit.randomizerWithdrawRabbit(_to, _amount);
    }

    function setRefundsAreOn(bool _refundsAreOn) external onlyOwner {
        karrotChef.setRefundsAreOn(_refundsAreOn);
        rabbit.setRefundsAreOn(_refundsAreOn);
    }

    //======================================================================================
    // NEW SETTERS FOR FULL PROTEC
    //======================================================================================

    function openFullProtecDeposits() external onlyOwner {
        karrotFullProtec.openFullProtecDeposits();
    }

    function setFullProtecLockDuration(uint32 _lockDuration) external onlyOwner {
        karrotFullProtec.setFullProtecLockDuration(_lockDuration);
    }

    function setThresholdFullProtecKarrotBalance(uint224 _thresholdFullProtecKarrotBalance) external onlyOwner {
        karrotFullProtec.setThresholdFullProtecKarrotBalance(_thresholdFullProtecKarrotBalance);
    }

    //======================================================================================
    // NEW SETTERS FOR STOLEN POOL 
    //======================================================================================

    function setAttackBurnPercentage(uint16 _attackBurnPercentage) external onlyOwner {
        stolenPool.setAttackBurnPercentage(_attackBurnPercentage);
    }

    function setStolenPoolEpochLength(uint32 _stolenPoolEpochLength) external onlyOwner {
        stolenPool.setStolenPoolEpochLength(_stolenPoolEpochLength);
    }

}

