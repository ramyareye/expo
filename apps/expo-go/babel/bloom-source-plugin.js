module.exports = function bloomSourcePlugin({ types: t }) {
  return {
    name: 'bloom-source-plugin',
    visitor: {
      JSXFragment() {
        // Fragments cannot accept custom props.
      },
      JSXOpeningElement(path, state) {
        const nameNode = path.node.name;
        if (t.isJSXIdentifier(nameNode) && nameNode.name === 'Fragment') {
          return;
        }
        if (
          t.isJSXMemberExpression(nameNode) &&
          t.isJSXIdentifier(nameNode.object, { name: 'React' }) &&
          t.isJSXIdentifier(nameNode.property, { name: 'Fragment' })
        ) {
          return;
        }
        const filename = state.file?.opts?.filename;
        if (!filename || filename.includes('node_modules')) {
          return;
        }
        const loc = path.node.loc;
        if (!loc) {
          return;
        }
        const hasAttribute = path.node.attributes.some(
          (attr) =>
            t.isJSXAttribute(attr) && t.isJSXIdentifier(attr.name, { name: '__bloomSource' })
        );
        if (hasAttribute) {
          return;
        }
        const fileName = filename.replace(/\\/g, '/');
        const sourceObject = t.objectExpression([
          t.objectProperty(t.identifier('fileName'), t.stringLiteral(fileName)),
          t.objectProperty(t.identifier('lineNumber'), t.numericLiteral(loc.start.line)),
          t.objectProperty(t.identifier('columnNumber'), t.numericLiteral(loc.start.column + 1)),
        ]);
        path.node.attributes.push(
          t.jsxAttribute(t.jsxIdentifier('__bloomSource'), t.jsxExpressionContainer(sourceObject))
        );
      },
    },
  };
};
