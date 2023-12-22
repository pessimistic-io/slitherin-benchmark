// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

import "./ERC20PresetMinterRebaser.sol";

// ______  ___  _   _ _____ _   __
// | ___ \/ _ \| \ | |_   _| | / /
// | |_/ / /_\ \  \| | | | | |/ / 
// |  __/|  _  | . ` | | | |    \ 
// | |   | | | | |\  |_| |_| |\  \
// \_|   \_| |_|_| \_/\___/\_| \_/

// Website: www.dankmemeswap.com
// Twitter: https://twitter.com/dankmemeswap

abstract contract IPANIK {
    event Rebase(
        uint256 epoch,
        uint256 prevPanikScalingFactor,
        uint256 newPanikScalingFactor
    );

    event Mint(address to, uint256 amount);
    event Burn(address from, uint256 amount);
}


contract Panik is ERC20PresetMinterRebaser, Ownable, IPANIK {
    using SafeMath for uint256;

    bool internal _notEntered;

    uint256 public constant internalDecimals = 10**24;

    uint256 public constant BASE = 10**18;

    uint256 public panikScalingFactor;

    mapping(address => uint256) internal _panikBalances;

    mapping(address => mapping(address => uint256)) internal _allowedFragments;

    uint256 public initSupply;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 public DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    uint256 private INIT_SUPPLY = 6969696969696 * 10**18;
    uint256 private _totalSupply;

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    constructor() ERC20PresetMinterRebaser("Panik", "PANIK") {
        panikScalingFactor = BASE;
        initSupply = _fragmentToPanik(INIT_SUPPLY);
        _totalSupply = INIT_SUPPLY;
        _panikBalances[owner()] = initSupply;

        emit Transfer(address(0), msg.sender, INIT_SUPPLY);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function maxScalingFactor() external view returns (uint256) {
        return _maxScalingFactor();
    }

    function _maxScalingFactor() internal view returns (uint256) {
        // scaling factor can only go up to 2**256-1 = initSupply * panikScalingFactor
        // this is used to check if panikScalingFactor will be too high to compute balances when rebasing.
        return uint256(int256(-1)) / initSupply;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role");

        _mint(to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal override {
        _totalSupply = _totalSupply.add(amount);

        // get underlying value
        uint256 panikValue = _fragmentToPanik(amount);

        initSupply = initSupply.add(panikValue);

        // make sure the mint didnt push maxScalingFactor too low
        require(
            panikScalingFactor <= _maxScalingFactor(),
            "max scaling factor too low"
        );

        // add balance
        _panikBalances[to] = _panikBalances[to].add(panikValue);

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) public override {
        _burn(amount);
    }

    function _burn(uint256 amount) internal {
        // decrease totalSupply
        _totalSupply = _totalSupply.sub(amount);

        // get underlying value
        uint256 panikValue = _fragmentToPanik(amount);

        // decrease initSupply
        initSupply = initSupply.sub(panikValue);

        // decrease balance
        _panikBalances[msg.sender] = _panikBalances[msg.sender].sub(panikValue);
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @notice Mints new tokens using underlying amount, increasing totalSupply, initSupply, and a users balance.
     */
    function mintUnderlying(address to, uint256 amount) public returns (bool) {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role");

        _mintUnderlying(to, amount);
        return true;
    }

    function _mintUnderlying(address to, uint256 amount) internal {
        // increase initSupply
        initSupply = initSupply.add(amount);

        // get external value
        uint256 scaledAmount = _panikToFragment(amount);

        // increase totalSupply
        _totalSupply = _totalSupply.add(scaledAmount);

        // make sure the mint didnt push maxScalingFactor too low
        require(
            panikScalingFactor <= _maxScalingFactor(),
            "max scaling factor too low"
        );

        // add balance
        _panikBalances[to] = _panikBalances[to].add(amount);

        emit Mint(to, scaledAmount);
        emit Transfer(address(0), to, scaledAmount);
    }

    function transferUnderlying(address to, uint256 value)
        public
        validRecipient(to)
        returns (bool)
    {
        // sub from balance of sender
        _panikBalances[msg.sender] = _panikBalances[msg.sender].sub(value);

        // add to balance of receiver
        _panikBalances[to] = _panikBalances[to].add(value);
        emit Transfer(msg.sender, to, _panikToFragment(value));
        return true;
    }

    function transfer(address to, uint256 value)
        public
        override
        validRecipient(to)
        returns (bool)
    {
        // minimum transfer value == panikScalingFactor / 1e24;
        uint256 panikValue = _fragmentToPanik(value);

        _panikBalances[msg.sender] = _panikBalances[msg.sender].sub(panikValue);

        _panikBalances[to] = _panikBalances[to].add(panikValue);
        emit Transfer(msg.sender, to, value);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override validRecipient(to) returns (bool) {
        _allowedFragments[from][msg.sender] = _allowedFragments[from][
            msg.sender
        ].sub(value);

        uint256 panikValue = _fragmentToPanik(value);

        _panikBalances[from] = _panikBalances[from].sub(panikValue);
        _panikBalances[to] = _panikBalances[to].add(panikValue);
        emit Transfer(from, to, value);

        return true;
    }

    function balanceOf(address who) public view override returns (uint256) {
        return _panikToFragment(_panikBalances[who]);
    }

    function balanceOfUnderlying(address who) public view returns (uint256) {
        return _panikBalances[who];
    }

    function allowance(address owner_, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function approve(address spender, uint256 value)
        public
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function rebase(
        uint256 epoch,
        uint256 indexDelta,
        bool positive
    ) public returns (uint256) {
        require(hasRole(REBASER_ROLE, _msgSender()), "Rebaser role required");

        if (indexDelta == 0) {
            emit Rebase(epoch, panikScalingFactor, panikScalingFactor);
            return _totalSupply;
        }

        uint256 prevPanikScalingFactor = panikScalingFactor;

        if (!positive) {
            // negative rebase, decrease scaling factor
            panikScalingFactor = panikScalingFactor
                .mul(BASE.sub(indexDelta))
                .div(BASE);
        } else {
            // positive rebase, increase scaling factor
            uint256 newScalingFactor = panikScalingFactor
                .mul(BASE.add(indexDelta))
                .div(BASE);
            if (newScalingFactor < _maxScalingFactor()) {
                panikScalingFactor = newScalingFactor;
            } else {
                panikScalingFactor = _maxScalingFactor();
            }
        }

        emit Rebase(epoch, prevPanikScalingFactor, panikScalingFactor);
        _totalSupply = _panikToFragment(initSupply);
        return _totalSupply;
    }

    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) public onlyOwner returns (bool) {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= deadline, "PANIK/permit-expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );

        require(owner != address(0), "PANIK/invalid-address-0");
        require(owner == ecrecover(digest, v, r, s), "PANIK/invalid-permit");
        _allowedFragments[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function panikToFragment(uint256 panik) public view returns (uint256) {
        return _panikToFragment(panik);
    }

    function fragmentToPanik(uint256 value) public view returns (uint256) {
        return _fragmentToPanik(value);
    }

    function _panikToFragment(uint256 panik) internal view returns (uint256) {
        return panik.mul(panikScalingFactor).div(internalDecimals);
    }

    function _fragmentToPanik(uint256 value) internal view returns (uint256) {
        return value.mul(internalDecimals).div(panikScalingFactor);
    }

}
