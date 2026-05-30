// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title HookMiner
/// @notice Finds a CREATE2 salt that places a hook at an address whose low 14 bits equal the
///         desired Uniswap v4 permission flags. v4 derives a hook's permissions from its
///         address, and {LambdaHook}'s constructor reverts unless they match — so deployment
///         must target a mined address via CREATE2.
/// @dev    Mirrors the canonical v4-periphery miner. `deployer` is the CREATE2 factory the
///         broadcast uses (Foundry's deterministic deployer by default). Run off-chain / in a
///         script: it loops salts until the computed address carries exactly `flags`.
library HookMiner {
    /// @notice Mask for the 14 permission bits v4 reads from a hook address.
    uint160 internal constant FLAG_MASK = 0x3FFF;

    /// @notice Bound on the salt search; ample for any single flag combination.
    uint256 internal constant MAX_LOOP = 160_444;

    error HookAddressNotFound();

    /// @param deployer   The CREATE2 deployer (Foundry deterministic deployer:
    ///                    0x4e59b44847b379578588920cA78FbF26c0B4956C).
    /// @param flags      Desired permission bits (e.g. BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG | …).
    /// @param creationCode  `type(Hook).creationCode`.
    /// @param constructorArgs  abi.encode(...) of the hook's constructor arguments.
    /// @return hookAddress  The mined address.
    /// @return salt         The salt that produces it.
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        bytes32 initCodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));
        for (uint256 i; i < MAX_LOOP; ++i) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, initCodeHash);
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, salt);
            }
        }
        revert HookAddressNotFound();
    }

    /// @notice The CREATE2 address for a given deployer/salt/init-code hash.
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
