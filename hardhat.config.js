const {subtask} = require('hardhat/config');
const {TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD} = require('hardhat/builtin-tasks/task-names');
const solc = require('solc');

// Use the npm-locked compiler, without a separate compiler download.
// https://v2.hardhat.org/hardhat-runner/docs/other-guides/using-custom-solc
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD).setAction(async ({solcVersion}, _hre, runSuper) => {
  if (solcVersion !== '0.8.16') return runSuper();
  if (!solc.version().startsWith('0.8.16+commit.07a7930e')) {
    throw new Error('Expected the pinned Solidity 0.8.16 compiler; run npm ci.');
  }
  return {
    compilerPath: require.resolve('solc/soljson.js'),
    isSolcJs: true,
    version: solcVersion,
    longVersion: solc.version(),
  };
});

// Build-only configuration: no target network, deployment account or secrets.
module.exports = {
  solidity: {
    version: '0.8.16',
    settings: {
      optimizer: {enabled: true, runs: 10},
      viaIR: true,
      evmVersion: 'london',
    },
  },
};
