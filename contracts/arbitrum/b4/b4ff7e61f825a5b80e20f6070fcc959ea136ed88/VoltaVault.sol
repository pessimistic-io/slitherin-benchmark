// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

interface IVolt is IERC20 {
    function decimals() external view returns(uint8);
}

interface IPriceSource {
    function getPrice() external view returns(uint);
}

contract VoltaVaultNFT is ERC721Enumerable {
    string public uri;

    constructor(
        string memory name,
        string memory symbol,
        string memory _uri
    )
        ERC721(name, symbol)
    {
        uri = _uri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return bytes(uri).length > 0 ? string(abi.encodePacked(uri, tokenId)) : "";
    }
}

interface Fees {
	function getRepaymentFees(address user) external view returns(uint);
}

contract Vault is ReentrancyGuard, VoltaVaultNFT {
    IPriceSource public CollateralPriceSource;

    using SafeERC20 for IVolt;

    Fees public feesContract;
    uint256 public _minimumCollateralPercentage;

    uint256 public vaultCount;

    uint256 public minDebt;

    address public treasury;
    uint256 public tokenPeg;

    mapping(uint256 => uint256) public vaultCollateral;
    mapping(uint256 => uint256) public vaultDebt;

    address public stabilityPool;

    IVolt public collateral;
    IVolt public volt;

    uint256 public priceSourceDecimals;
    uint256 public totalBorrowed;
    uint256 public maxPerVault;

    uint8 public version = 1;

    event CreateVault(uint256 vaultID, address creator);
    event DestroyVault(uint256 vaultID);
    event TransferVault(uint256 vaultID, address from, address to);
    event DepositCollateral(uint256 vaultID, uint256 amount);
    event WithdrawCollateral(uint256 vaultID, uint256 amount);
    event BorrowToken(uint256 vaultID, uint256 amount);
    event PayBackToken(uint256 vaultID, uint256 amount, uint256 closingFee);
    event LiquidateVault(
        uint256 vaultID,
        address owner,
        address buyer,
        uint256 debtRepaid,
        uint256 collateralLiquidated,
        uint256 closingFee
    );

    constructor(
        address CollateralPriceSourceAddress,
        uint256 minimumCollateralPercentage,
        string memory name,
        string memory symbol,
        address _volt,
        address _collateral,
        string memory baseURI,
        address fees_,
        uint _maxPerVault
    ) VoltaVaultNFT(name, symbol, baseURI) {
        require(CollateralPriceSourceAddress != address(0));
        require(minimumCollateralPercentage != 0);

        CollateralPriceSource = IPriceSource(CollateralPriceSourceAddress);
        stabilityPool = address(0);
        tokenPeg = 1e18; // $1

        _minimumCollateralPercentage = minimumCollateralPercentage;

        collateral = IVolt(_collateral);
        volt = IVolt(_volt);
        
        priceSourceDecimals = 18;
        feesContract = Fees(fees_);

        maxPerVault = _maxPerVault;
    }

    modifier onlyVaultOwner(uint256 vaultID) {
        require(_exists(vaultID), "Vault does not exist");
        require(ownerOf(vaultID) == msg.sender, "Vault is not owned by you");
        _;
    }

    function getDebtCeiling() public view returns (uint256) {
        return volt.balanceOf(address(this));
    }

    function exists(uint256 vaultID) external view returns (bool) {
        return _exists(vaultID);
    }

    function getClosingFee() public view returns (uint256) {
        return feesContract.getRepaymentFees(msg.sender);
    }

    function getTokenPriceSource() public view returns (uint256) {
        return tokenPeg;
    }

    function getCollateralPrice() public view returns (uint256 price) {
        price = CollateralPriceSource.getPrice();
    }

    function calculateCollateralProperties(uint256 _collateral, uint256 _debt)
        private
        view
        returns (uint256, uint256)
    {
        require(getCollateralPrice() != 0);
        require(getTokenPriceSource() != 0);

        uint256 collateralValue = _collateral * getCollateralPrice();

        uint256 debtValue = _debt * getTokenPriceSource();
        uint256 collateralValueTimes100 = collateralValue * 100;

        return (collateralValueTimes100, debtValue);
    }

    function isValidCollateral(uint256 _collateral, uint256 _debt)
        private
        view
        returns (bool)
    {
        (
            uint256 collateralValueTimes100,
            uint256 debtValue
        ) = calculateCollateralProperties(_collateral, _debt);

        uint256 collateralPercentage = collateralValueTimes100 * 1e18 / debtValue;

        return collateralPercentage >= _minimumCollateralPercentage;
    }

    function createVault() external returns (uint256) {
        uint256 id = vaultCount;
        vaultCount = vaultCount + 1;

        _mint(msg.sender, id);

        emit CreateVault(id, msg.sender);
        return id;
    }

    function destroyVault(uint256 vaultID)
        external
        onlyVaultOwner(vaultID)
        nonReentrant
    {
        require(vaultDebt[vaultID] == 0, "Vault has outstanding debt");

        if (vaultCollateral[vaultID] != 0) {
            // withdraw leftover collateral
            collateral.safeTransfer(ownerOf(vaultID), vaultCollateral[vaultID]);
        }

        _burn(vaultID);

        delete vaultCollateral[vaultID];
        delete vaultDebt[vaultID];

        emit DestroyVault(vaultID);
    }

    function depositCollateral(uint256 vaultID, uint256 amount) external {
        require(_exists(vaultID), "Vault does not exist");
        require(amount + vaultCollateral[vaultID] <= maxPerVault, "!max");

        collateral.safeTransferFrom(msg.sender, address(this), amount);

        uint256 newCollateral = vaultCollateral[vaultID] + amount;
        vaultCollateral[vaultID] = newCollateral;

        emit DepositCollateral(vaultID, amount);
    }

    function withdrawCollateral(uint256 vaultID, uint256 amount)
        external
        onlyVaultOwner(vaultID)
        nonReentrant
    {
        require(
            vaultCollateral[vaultID] >= amount,
            "Vault does not have enough collateral"
        );

        uint256 newCollateral = vaultCollateral[vaultID] - amount;

        if (vaultDebt[vaultID] != 0) {
            require(
                isValidCollateral(newCollateral, vaultDebt[vaultID]),
                "Withdrawal would put vault below minimum collateral percentage"
            );
        }

        vaultCollateral[vaultID] = newCollateral;
        collateral.safeTransfer(msg.sender, amount);

        emit WithdrawCollateral(vaultID, amount);
    }

    function borrowToken(uint256 vaultID, uint256 amount)
        external
        onlyVaultOwner(vaultID)
    {
        require(amount > 0, "Must borrow non-zero amount");
        require(
            amount <= getDebtCeiling(),
            "borrowToken: Cannot mint over available supply."
        );

        uint256 newDebt = vaultDebt[vaultID] + amount;

        require(
            isValidCollateral(vaultCollateral[vaultID], newDebt),
            "Borrow would put vault below minimum collateral percentage"
        );

        require(
            (vaultDebt[vaultID] + amount) >= minDebt, 
            "Vault debt can't be under minDebt"
        );

        vaultDebt[vaultID] = newDebt;
        volt.safeTransfer(msg.sender, amount);
        totalBorrowed = totalBorrowed + amount;

        emit BorrowToken(vaultID, amount);
    }

    function payBackToken(uint256 vaultID, uint256 amount) external {
        require(volt.balanceOf(msg.sender) >= amount, "Token balance too low");
        uint closingFee = getClosingFee();

        if(amount > vaultDebt[vaultID]) {
            amount = vaultDebt[vaultID];
        }

        require(
            (vaultDebt[vaultID] - amount) >= minDebt ||
            amount == (vaultDebt[vaultID]), 
            "Vault debt can't be under minDebt"
        );

        uint256 _closingFee = (
            amount * closingFee * getTokenPriceSource()
        ) / (
            getCollateralPrice() * 1e6
        );

        volt.safeTransferFrom(msg.sender, address(this), amount);

        vaultDebt[vaultID] = vaultDebt[vaultID] - amount;
        vaultCollateral[vaultID] = vaultCollateral[vaultID] - _closingFee;
        totalBorrowed = totalBorrowed - amount;

        collateral.safeTransfer(treasury, _closingFee);

        emit PayBackToken(vaultID, amount, _closingFee);
    }

    function checkCost(uint256 vaultID) public view returns (uint256) {
        if (
            vaultCollateral[vaultID] == 0 ||
            vaultDebt[vaultID] == 0 ||
            !checkLiquidation(vaultID)
        ) {
            return 0;
        }

        (
            ,
            uint256 debtValue
        ) = calculateCollateralProperties(
            vaultCollateral[vaultID],
            vaultDebt[vaultID]
        );

        if (debtValue == 0) {
            return 0;
        }

        debtValue = debtValue / (10**priceSourceDecimals);

        return (debtValue);
    }

    function checkCollateralPercentage(uint256 vaultID)
        public
        view
        returns (uint256 percent)
    {
        require(_exists(vaultID), "Vault does not exist");

        if (vaultCollateral[vaultID] == 0 || vaultDebt[vaultID] == 0) {
            return 0;
        }
        (
            uint256 collateralValueTimes100,
            uint256 debtValue
        ) = calculateCollateralProperties(
            vaultCollateral[vaultID],
            vaultDebt[vaultID]
        );

        percent = collateralValueTimes100 * 1e18 / debtValue;
    }

    function checkLiquidation(uint256 vaultID) public view returns (bool) {

        uint percent = checkCollateralPercentage(vaultID);

        if (percent == 0) {
            return false;
        }

        if (percent < _minimumCollateralPercentage) {
            return true;
        } else {
            return false;
        }
    }

    function liquidateVaultReward(uint256 vaultID) public view returns(uint, uint) {
        (uint256 collateralValueTimes100, uint256 debtValue) = calculateCollateralProperties(vaultCollateral[vaultID], vaultDebt[vaultID]);

        uint256 collateralPercentage = collateralValueTimes100 * 1e18 / debtValue;
        uint256 collateralExtract = vaultCollateral[vaultID];
        uint actualDiscount = 100e18 * 1e18 / collateralPercentage;
        uint liquidatorDiscount = 100e18 * 1e18 / _minimumCollateralPercentage;
        uint earnFees = ((1e18 - liquidatorDiscount) / 2);

        uint liquidatorEarned;
        uint protocolEarned;
        if(actualDiscount + earnFees >= 1e18) {
            liquidatorEarned = 1e18;
            protocolEarned = 0;
        } else {
            liquidatorEarned = actualDiscount + earnFees;
            protocolEarned = 1e18 - liquidatorEarned;
        }

        return (
            collateralExtract * liquidatorEarned / 1e18,
            collateralExtract * protocolEarned / 1e18 
        );
    }

    function liquidateVault(uint256 vaultID) external {
        require(_exists(vaultID), "Vault does not exist");
        require(
            stabilityPool == address(0) || msg.sender == stabilityPool,
            "liquidation is disabled for public"
        );

        (
            uint256 collateralValueTimes100,
            uint256 debtValue
        ) = calculateCollateralProperties(
            vaultCollateral[vaultID],
            vaultDebt[vaultID]
        );

        require(debtValue > 0, "No debt");

        uint256 collateralPercentage = collateralValueTimes100 * 1e18 / debtValue;

        require(
            collateralPercentage < _minimumCollateralPercentage,
            "Vault is not below minimum collateral percentage"
        );

        debtValue = debtValue / (10**priceSourceDecimals);

        require(
            volt.balanceOf(msg.sender) >= debtValue,
            "Token balance too low to pay off outstanding debt"
        );

        uint256 collateralExtract = vaultCollateral[vaultID];
        (uint toSendLiquidator, uint toSendProtocol) = liquidateVaultReward(vaultID);

        volt.safeTransferFrom(msg.sender, address(this), debtValue);
        totalBorrowed = totalBorrowed - debtValue;
        vaultDebt[vaultID] = 0;

        if(toSendProtocol != 0) collateral.safeTransfer(treasury, toSendProtocol);
        vaultCollateral[vaultID] = 0;
        collateral.safeTransfer(msg.sender, toSendLiquidator);

        emit LiquidateVault(
            vaultID,
            ownerOf(vaultID),
            msg.sender,
            debtValue,
            collateralExtract,
            toSendProtocol
        );
    }

    function getUserVault(address _user, uint _i) external view 
    returns(
        uint _vaultId,
        address _owner,
        uint _collateral, 
        uint _debt, 
        uint _percent,
        uint _collateralValue,
        uint _debtValue,
        uint _minDebt,
        uint __minimumCollateralPercentage,
        address _collateralAsset,
        address _debtAsset,
        address _vault
    ) {
        _vaultId = tokenOfOwnerByIndex(_user, _i);
        return getVault(_vaultId);
    }

    function getVault(uint _i) public view 
    returns(
        uint _vaultId,
        address _owner,
        uint _collateral, 
        uint _debt, 
        uint _percent,
        uint _collateralValue,
        uint _debtValue,
        uint _minDebt,
        uint __minimumCollateralPercentage,
        address _collateralAsset,
        address _debtAsset,
        address _vault
    ) {
        _vaultId = _i;
        _owner = ownerOf(_i);
        _collateral = vaultCollateral[_vaultId];
        _debt = vaultDebt[_vaultId];

        (
            uint256 collateralValueTimes100,
            uint256 debtValue
        ) = calculateCollateralProperties(
            _collateral,
            _debt
        );

        _percent = debtValue == 0 ? (2**256 - 1) : (collateralValueTimes100 * 1e18 / debtValue);

        _collateralValue = collateralValueTimes100 / 100 / (10**priceSourceDecimals);
        _debtValue = debtValue / (10**priceSourceDecimals);
        _minDebt = minDebt;
        __minimumCollateralPercentage = _minimumCollateralPercentage;
        _collateralAsset = address(collateral);
        _debtAsset = address(volt);
        _vault = address(this);
    }
}

contract VoltaVault is Vault, Ownable {
    constructor(
        address CollateralPriceSourceAddress,
        uint256 minimumCollateralPercentage,
        string memory name,
        string memory symbol,
        address _volt,
        address _collateral,
        string memory baseURI,
        address _treasury,
        address fees_,
        uint _max
    )
    Vault(
        CollateralPriceSourceAddress,
        minimumCollateralPercentage,
        name,
        symbol,
        _volt,
        _collateral,
        baseURI,
        fees_,
        _max
    )
    {
        treasury = _treasury;
    }

    function changeCollateralPriceSource(address CollateralPriceSourceAddress)
        external
        onlyOwner
    {
        CollateralPriceSource = IPriceSource(CollateralPriceSourceAddress);
    }

    function setStabilityPool(address _pool) external onlyOwner {
        stabilityPool = _pool;
    }

    function setMaxPerVault(uint _max) external onlyOwner {
        maxPerVault = _max;
    }

    function setFeesContract(address _fees) external onlyOwner {
        feesContract = Fees(_fees);
    }

    function setMinCollateralRatio(uint256 minimumCollateralPercentage)
        external
        onlyOwner
    {
        _minimumCollateralPercentage = minimumCollateralPercentage;
    }

    function setMinDebt(uint256 _minDebt)
        external
        onlyOwner
    {
        minDebt = _minDebt;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero address");
        treasury = _treasury;
    }

    function recover(uint256 amountToken, address _address) public onlyOwner {
        volt.transfer(_address, amountToken);
    }

    function setTokenURI(string memory _uri) public onlyOwner {
        uri = _uri;
    }
}
