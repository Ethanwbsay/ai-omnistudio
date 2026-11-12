import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/widgets/math_content.dart';

void main() {
  testWidgets('renders inline and display LaTeX expressions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content:
                r'Pythagorean: $a^2+b^2=c^2$. $$x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}$$',
          ),
        ),
      ),
    );

    expect(find.byType(RichText), findsWidgets);
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('falls back to source text for invalid LaTeX', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(content: r'Broken: $n \left$'),
        ),
      ),
    );

    expect(find.text(r'n \left'), findsOneWidget);
    expect(find.textContaining('Parser Error'), findsNothing);
  });

  testWidgets('renders bare LaTeX-only lines as display equations',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''A=\operatorname{diag}(a_1,a_2,a_3),\qquad
A^{-1}=\operatorname{diag}\left(3,4,7\right).''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('renders common Markdown without exposing control markers',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: '''# 一、稳定性条件

## 1. 建立电路方程

- 左侧电压源：12 V
- 右侧电流：**向下**

---

| 参数 | 数值 |
| --- | --- |
| 电阻 | 10 Ω |

> 请注意开关状态。''',
          ),
        ),
      ),
    );

    expect(
        find.byWidgetPredicate((widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('一、稳定性条件')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('左侧电压源：12 V')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is RichText && widget.text.toPlainText().contains('向下')),
        findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('# 一、稳定性条件'), findsNothing);
    expect(find.text('---'), findsNothing);
  });

  testWidgets('renders bare LaTeX fragments inside Chinese explanations',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''电感电流为 i_L(t)，其中
u_C(t)=\frac{1}{C}\int_0^t i_C(\tau)\,d\tau,
并且稳态时 u_R=\frac{U}{R}=10\mathrm{V}。''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\frac'), findsNothing);
    expect(find.textContaining(r'\mathrm'), findsNothing);
    expect(find.textContaining(r'\tau'), findsNothing);
  });

  testWidgets('groups multiline boxed cases into one equation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''线上，电容电压为
\boxed{
u_C(t)=
\begin{cases}
-3e^{-3t/8}, & 0\le t<2,\\[6pt]
\displaystyle
\frac{4}{3} + 3e^{-3/4}e^{-3(t-2)/8},
& 2\le t<3,\\[10pt]
\displaystyle
\left[
\frac{4}{3} -
\left(\frac{4}{3}+3e^{-3/4}\right)e^{-3/8}
\right]e^{-3(t-3)/8},
& 3\le t<4,\\[10pt]
\displaystyle
\left\{
\frac{1}{4}+
\left[
\frac{4}{3} -
\left(\frac{4}{3}+3e^{-3/4}\right)e^{-3/8}
\right]e^{-3/8}
\right\}e^{-3(t-4)/8},
& t>4.
\end{cases}
}
并且在 t=4 处有''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.textContaining(r'\displaystyle'), findsNothing);
    expect(find.textContaining(r'\end{cases}'), findsNothing);
  });

  testWidgets('keeps a truncated boxed formula as one rendered block',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''\boxed{
u_C(t)=
\left\{
\frac{1}{4}+
\left[
\frac{4}{3}-\left(\frac{4}{3}+3e^{-3/4}\right)e^{-3/8}
\right]e^{-3/8}
\right\}e^{-3(t-4)/8},
V''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\left\{'), findsNothing);
    expect(find.textContaining(r'\right\}'), findsNothing);
  });

  testWidgets(
      'groups boxed formulas with left-right delimiters and trailing text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''\boxed{
u_C(t)=
\left\{
\frac{1}{4}+
\left[
\frac{4}{3}-\left(\frac{4}{3}+3e^{-3/4}\right)e^{-3/8}
\right]e^{-3/8}
\right\}
e^{-3(t-4)/8},
V
},''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\left\{'), findsNothing);
    expect(find.textContaining(r'\right\}'), findsNothing);
    expect(find.textContaining(r'\left['), findsNothing);
  });

  testWidgets('groups an unboxed cases environment', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''由于
u(-n-1)=1\Longleftrightarrow n\le -1,
所以该序列是左边序列：
x[n]=
\begin{cases}
|n-2|=2-n,&n\le -1,\\
0,&n\ge 0.
\end{cases}
采用通常的 z 变换定义''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.textContaining(r'\end{cases}'), findsNothing);
  });

  testWidgets('groups boxed cases with dfrac and row spacing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''也可以写成分段形式：
\boxed{
h(n)=
\begin{cases}
-\frac{3^{n+1}}{8}, & n\le -1,\\[6pt]
-\dfrac{1}{8\cdot 3^{n-1}}, & n\ge 0
\end{cases}
}''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\dfrac'), findsNothing);
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
  });

  testWidgets('renders the unboxed cases format from the signal example',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''由于
u(-n-1)=1\Longleftrightarrow n\le -1,
所以该序列是左边序列：
x[n]=
\begin{cases}
|n-2|=2-n,&n\le -1,\\
0,&n\ge 0.
\end{cases}
采用通常的 z 变换定义''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.textContaining(r'\end{cases}'), findsNothing);
    expect(find.textContaining(r'\Longleftrightarrow'), findsNothing);
  });

  testWidgets('renders the boxed dfrac format from the second example',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''也可以写成分段形式：
\boxed{
h(n)=
\begin{cases}
-\frac{3^{n+1}}{8}, & n\le -1,\\[6pt]
-\dfrac{1}{8\cdot 3^{n-1}}, & n\ge 0
\end{cases}
}''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.textContaining(r'\dfrac'), findsNothing);
    expect(find.textContaining(r'\[6pt]'), findsNothing);
  });

  testWidgets('keeps nested Markdown delimiters inside boxed cases together',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''所以系统的单位样值响应为
\boxed{
h(n)=
$$-\frac{3}{8}3^n u(-n-1)$$
$$-\frac{3}{8}\left(\frac{1}{3}\right)^n u(n)$$
}
也可以写成分段形式：
\boxed{
h(n)=
\begin{cases}
$-\frac{3^{n+1}}{8}, & n\le -1,\\[6pt]$
$-\dfrac{1}{8\cdot 3^{n-1}}, & n\ge 0$
\end{cases}
}''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.textContaining(r'\dfrac'), findsNothing);
  });

  testWidgets('keeps bracket-delimited rows inside a boxed formula together',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''\boxed{
h(n)=
\[
-\frac{3}{8}3^n u(-n-1)
\]
\[
-\frac{3}{8}\left(\frac{1}{3}\right)^n u(n)
\]
}''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
  });

  testWidgets('does not split boxed cases after standalone dollar delimiters',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''Display form:
$$
\boxed{
h(n)=
\begin{cases}
-\frac{3^{n+1}}{8}, & n\le -1,\\[6pt]
-\dfrac{1}{8\cdot 3^{n-1}}, & n\ge 0
\end{cases}
}
$$
where $u(n)$ is a unit-step sequence.
$$
\boxed{\frac{1}{3}<|z|<3}
$$''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(3));
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\begin{cases}'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

  testWidgets('accepts a display delimiter before boxed on the same line',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''$$\boxed{
h(n)=\begin{cases}
1,&n<0\\
0,&n\ge0
\end{cases}
}$$''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

  testWidgets('repairs escaped Markdown and bare algebra from the solver',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''整理为
(z^{-1}-\frac{10}{3}+z)Y_+(z)=
X_+(z)-y(-1)+zy(0).

可见，单边变换确实会出现初始条件 \$y(-1)\$

\-\-\-

\#\# 3．为什么本题使用双边变换？

对于一个\*\*稳定的离散时间 LTI 单位样值响应 \$h(n)\$，有
\-\infty<n<\infty.

\#\# 4．结论

\$\$ 
\mathcal{Z}\{y(n-1)\}=z^{-1}Y(z)
\$\$''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(6));
    expect(find.byType(Divider), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is RichText && widget.text.toPlainText().contains('为什么本题使用双边变换？')),
      findsOneWidget,
    );
    expect(find.textContaining(r'\$y(-1)\$'), findsNothing);
    expect(find.textContaining(r'\#\#'), findsNothing);
    expect(find.textContaining(r'\*\*稳定'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

  testWidgets('renders escaped matrix equations and strips unsupported tags',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''\#\# 答案

按照图中 \\$I_2\\$ 从右向左的参考方向，

\\boxed{
\\begin{bmatrix}
I_1\\[4pt]
I_2
\\end{bmatrix}
=
\\begin{bmatrix}
1&0\\[4pt]
0&-1
\\end{bmatrix}
\\begin{bmatrix}
U_1\\[4pt]
U_2
\\end{bmatrix}
}

\-\-\-

\#\# 2．列 KCL 方程

I_2=j(V_R-U_1)-jV_R=(1-j)V_R-U_1.
\\tag{4}

\\boxed{
Y=
\\begin{bmatrix}
1&0\\\\
0&1
\\end{bmatrix}\\text{S}
}.
\\$\\$''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(4));
    expect(find.byType(Divider), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is RichText && widget.text.toPlainText().contains('答案')),
      findsOneWidget,
    );
    expect(find.textContaining(r'\begin{bmatrix}'), findsNothing);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\tag{4}'), findsNothing);
    expect(find.textContaining(r'\$I_2\$'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

  testWidgets('renders the literal matrix and tagged equations from the report',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathContent(
            content: r'''## 2．对左、右节点列方程

左节点流入网络的端口电流为

I_2=j(V_L-U_1)+V_L.
\tag{1}

右节点没有外加端口电流，按KCL：

(V_R-U_1)-jV_R=-I_2.
\tag{2}

并且有端口电压关系：

V_L-V_R=U_2.
\tag{3}

\boxed{
\begin{bmatrix}
I_1\\[4pt]
I_2
\end{bmatrix}
=
\begin{bmatrix}
1&0\\[4pt]
0&-1
\end{bmatrix}
\begin{bmatrix}
U_1\\[4pt]
U_2
\end{bmatrix}
}

因此二端口的 $Y$ 参数矩阵为

\boxed{
Y=
\begin{bmatrix}
1&0\\
0&1
\end{bmatrix}\text{S}
}.
$$''',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(6));
    expect(
      find.byWidgetPredicate((widget) =>
          widget is RichText && widget.text.toPlainText().contains('对左、右节点列方程')),
      findsOneWidget,
    );
    expect(find.textContaining(r'\begin{bmatrix}'), findsNothing);
    expect(find.textContaining(r'\tag{1}'), findsNothing);
    expect(find.textContaining(r'\tag{2}'), findsNothing);
    expect(find.textContaining(r'\tag{3}'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

  testWidgets('recovers formula rendering after an orphan display delimiter',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MathContent(
              content: r'''最终结果

$$\begin{bmatrix} I_1 \\ I_2 \end{bmatrix}
=
$$\begin{bmatrix} 1&0 \\ 0&1 \end{bmatrix}$$
\begin{bmatrix}
U_1\\
U_2
\end{bmatrix}.

所以二端口的 $Y$ 参数矩阵为：

\boxed{
Y=
\begin{bmatrix}
1&0\\
0&1
\end{bmatrix}\text{S}
}.
$$''',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsAtLeastNWidgets(4));
    expect(find.textContaining(r'\begin{bmatrix}'), findsNothing);
    expect(find.textContaining(r'\boxed'), findsNothing);
    expect(find.textContaining(r'\$Y\$'), findsNothing);
    expect(find.text(r'\$\$'), findsNothing);
  });

}
