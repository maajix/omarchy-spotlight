function create() {
  return { pending: {}, active: {}, failed: false }
}

function add(state, patch) {
  return {
    pending: Object.assign({}, state.pending, patch),
    active: state.active,
    failed: false
  }
}

function take(state) {
  if (state.failed || Object.keys(state.active).length || !Object.keys(state.pending).length)
    return { state: state, patch: null }
  return {
    state: { pending: {}, active: state.pending, failed: false },
    patch: state.pending
  }
}

function settle(state, saved) {
  return {
    pending: saved ? state.pending : Object.assign({}, state.active, state.pending),
    active: {},
    failed: !saved
  }
}

if (typeof module !== "undefined")
  module.exports = { create: create, add: add, take: take, settle: settle }
