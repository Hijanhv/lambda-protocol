// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice A minimal, openly-mintable ERC20 for testnet pools only. NOT for production —
///         anyone can mint. Used to stand up a tWETH/tUSDC pair on Unichain Sepolia so the
///         Lambda hook has a pool to manage.
contract TestToken is ERC20 {
    string private _n;
    string private _s;
    uint8 private immutable _d;

    constructor(string memory n_, string memory s_, uint8 d_) {
        _n = n_;
        _s = s_;
        _d = d_;
    }

    function name() public view override returns (string memory) {
        return _n;
    }

    function symbol() public view override returns (string memory) {
        return _s;
    }

    function decimals() public view override returns (uint8) {
        return _d;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Deploys a tWETH (18d) + tUSDC (6d) pair and mints a starting balance to the
///         broadcaster. Print the two addresses into TOKEN0/TOKEN1 for DeployUnichain.
/// @dev    `forge script contracts/script/DeployTestTokens.s.sol --rpc-url $UNICHAIN_RPC --private-key $PRIVATE_KEY --broadcast`
contract DeployTestTokens is Script {
    function run() external {
        uint256 wethAmt = vm.envOr("MINT_WETH", uint256(1_000_000 ether));
        uint256 usdcAmt = vm.envOr("MINT_USDC", uint256(1_000_000_000_000)); // 1,000,000 * 1e6

        vm.startBroadcast();
        TestToken weth = new TestToken("Test Wrapped Ether", "tWETH", 18);
        TestToken usdc = new TestToken("Test USD Coin", "tUSDC", 6);
        weth.mint(msg.sender, wethAmt);
        usdc.mint(msg.sender, usdcAmt);
        vm.stopBroadcast();

        console2.log("tWETH (18d)", address(weth));
        console2.log("tUSDC (6d) ", address(usdc));
        console2.log("minted to  ", msg.sender);
    }
}
