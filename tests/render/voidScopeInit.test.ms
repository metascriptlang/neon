import { accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { Host, HostNode } from "../../src/render/hostTypes";
import { mockHost, mockNode } from "../../src/render/host";
import { NoOwnerError, useContext } from "../../src/render/context";
import { VoidSpace, getVoidAreaContext, getVoidScopeContext, useVoidSpace } from "../../src/render/voidScope";

test "private Void scope lookup still requires an owner before any provider" {
	let refused = false;
	try { useVoidSpace(); }
	catch (error) { refused = error instanceof NoOwnerError; }
	assert refused;
}

test "private Void context keys remain stable and nearest providers restore the default" {
	createRoot((dispose: () => void): void => {
		try {
			assert useVoidSpace() === VoidSpace.Outside;
			const scope = getVoidScopeContext();
			const area = getVoidAreaContext();
			assert scope.key === getVoidScopeContext().key;
			assert area.key === getVoidAreaContext().key;
			assert useContext(area) === null;
			const host = mockHost();
			const root = mockNode("root");
			let visits: int32 = 0;
			scope.provider({
				value: accessor((): VoidSpace => VoidSpace.Scene3D),
				children: (outerHost: Host, outerParent: HostNode, outerBefore: HostNode | null): void => {
					assert useVoidSpace() === VoidSpace.Scene3D;
					visits += 1;
					scope.provider({
						value: accessor((): VoidSpace => VoidSpace.Scene2D),
						children: (innerHost: Host, innerParent: HostNode, innerBefore: HostNode | null): void => {
							assert useVoidSpace() === VoidSpace.Scene2D;
							assert useContext(area) === null;
							visits += 1;
						},
					})(outerHost, outerParent, outerBefore);
					assert useVoidSpace() === VoidSpace.Scene3D;
				},
			})(host, root as unknown as HostNode, null);
			assert visits === 2 && useVoidSpace() === VoidSpace.Outside;
			assert scope.key === getVoidScopeContext().key && area.key === getVoidAreaContext().key;
		} finally { dispose(); }
	});
}
